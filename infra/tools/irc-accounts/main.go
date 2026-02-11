package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"google.golang.org/api/iterator"
	secretmanagerpb "google.golang.org/genproto/googleapis/cloud/secretmanager/v1"
)

type config struct {
	action             string
	specificUser       string
	projectID          string
	secretOperPassword string
	ircHost            string
	ircPort            int
	tlsInsecure        bool
	timeout            time.Duration
	ergoConf           string
	ergoDB             string
	ergoBin            string
	dryRun             bool
	skipRestart        bool
}

type registerResult struct {
	username string
	status   string
}

func main() {
	var cfg config
	flag.StringVar(&cfg.action, "action", "list", "list, register, unregister, reset_all")
	flag.StringVar(&cfg.specificUser, "specific-user", "", "optional username to target")
	flag.StringVar(&cfg.projectID, "project-id", "analyze-this-2026", "GCP project ID")
	flag.StringVar(&cfg.secretOperPassword, "secret-oper-password", "irc-oper-password", "GCP secret name for oper password")
	flag.StringVar(&cfg.ircHost, "irc-host", "localhost", "IRC host")
	flag.IntVar(&cfg.ircPort, "irc-port", 6697, "IRC TLS port")
	flag.BoolVar(&cfg.tlsInsecure, "tls-insecure", true, "skip IRC TLS cert verification")
	flag.DurationVar(&cfg.timeout, "timeout", 15*time.Second, "IRC command timeout")
	flag.StringVar(&cfg.ergoConf, "ergo-conf", "/etc/ergo/ircd.yaml", "Ergo config path")
	flag.StringVar(&cfg.ergoDB, "ergo-db", "/var/lib/ergo/ircd.db", "Ergo database path")
	flag.StringVar(&cfg.ergoBin, "ergo-bin", "/usr/local/bin/ergo", "Ergo binary path")
	flag.BoolVar(&cfg.dryRun, "dry-run", false, "print planned actions without changing anything")
	flag.BoolVar(&cfg.skipRestart, "skip-restart", false, "skip restarting irccat/thelounge")
	flag.Parse()

	if err := run(context.Background(), cfg); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func run(ctx context.Context, cfg config) error {
	switch cfg.action {
	case "list", "register", "unregister", "reset_all":
	default:
		return fmt.Errorf("unknown action %q", cfg.action)
	}

	if cfg.action == "unregister" && cfg.specificUser == "" {
		return errors.New("specific-user is required for unregister")
	}

	client, err := secretmanager.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("create secret manager client: %w", err)
	}
	defer client.Close()

	var operPassword string
	if cfg.action != "list" {
		operPassword, err = accessSecret(ctx, client, cfg.projectID, cfg.secretOperPassword)
		if err != nil {
			return fmt.Errorf("load oper password: %w", err)
		}
	}

	if cfg.action == "reset_all" {
		log.Println("resetting IRC accounts (drop/reinit DB)")
		if cfg.dryRun {
			log.Println("dry-run: would stop irccat/thelounge/ergo, backup DB, initdb, start ergo")
		} else {
			if err := resetAll(cfg); err != nil {
				return err
			}
		}
	}

	var secrets []string
	if cfg.action == "list" || cfg.action == "register" || cfg.action == "reset_all" {
		if cfg.specificUser != "" {
			secrets = []string{cfg.specificUser + "-irc-passwd"}
		} else {
			secrets, err = listIrcSecrets(ctx, client, cfg.projectID)
			if err != nil {
				return err
			}
		}
	} else {
		secrets = []string{cfg.specificUser + "-irc-passwd"}
	}

	if len(secrets) == 0 {
		return errors.New("no IRC password secrets found")
	}

	usernames := make([]string, 0, len(secrets))
	for _, secret := range secrets {
		usernames = append(usernames, strings.TrimSuffix(secret, "-irc-passwd"))
	}
	log.Printf("will %s account(s): %s", cfg.action, strings.Join(usernames, ", "))

	if cfg.action == "list" {
		return nil
	}

	if cfg.dryRun {
		log.Println("dry-run: exiting without changes")
		return nil
	}

	if cfg.action != "reset_all" {
		if err := waitForErgo(cfg.ircHost, cfg.ircPort, 10*time.Second); err != nil {
			return err
		}
	}

	results := make([]registerResult, 0, len(usernames))
	for _, secret := range secrets {
		username := strings.TrimSuffix(secret, "-irc-passwd")
		switch cfg.action {
		case "register", "reset_all":
			password, err := accessSecret(ctx, client, cfg.projectID, secret)
			if err != nil {
				return fmt.Errorf("load password for %s: %w", username, err)
			}
			status, err := registerUser(cfg, operPassword, username, password)
			if err != nil {
				return err
			}
			results = append(results, registerResult{username: username, status: status})
		case "unregister":
			status, err := unregisterUser(cfg, operPassword, username)
			if err != nil {
				return err
			}
			results = append(results, registerResult{username: username, status: status})
		}
	}

	for _, res := range results {
		log.Printf("%s: %s", res.username, res.status)
	}

	if cfg.skipRestart {
		return nil
	}

	if cfg.action == "register" || cfg.action == "unregister" || cfg.action == "reset_all" {
		for _, svc := range []string{"irccat", "thelounge"} {
			if err := systemctl("restart", svc); err != nil {
				log.Printf("warning: restart %s failed: %v", svc, err)
			}
		}
	}

	return nil
}

func listIrcSecrets(ctx context.Context, client *secretmanager.Client, projectID string) ([]string, error) {
	parent := fmt.Sprintf("projects/%s", projectID)
	it := client.ListSecrets(ctx, &secretmanagerpb.ListSecretsRequest{Parent: parent})
	var secrets []string
	for {
		secret, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("list secrets: %w", err)
		}
		name := filepath.Base(secret.Name)
		if strings.HasSuffix(name, "-irc-passwd") {
			secrets = append(secrets, name)
		}
	}
	return secrets, nil
}

func accessSecret(ctx context.Context, client *secretmanager.Client, projectID, secretName string) (string, error) {
	name := fmt.Sprintf("projects/%s/secrets/%s/versions/latest", projectID, secretName)
	resp, err := client.AccessSecretVersion(ctx, &secretmanagerpb.AccessSecretVersionRequest{Name: name})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(resp.Payload.Data)), nil
}

func waitForErgo(host string, port int, timeout time.Duration) error {
	addr := fmt.Sprintf("%s:%d", host, port)
	deadline := time.Now().Add(timeout)
	for {
		conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
		if err == nil {
			_ = conn.Close()
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("ergo not reachable on %s within %s", addr, timeout)
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func resetAll(cfg config) error {
	for _, svc := range []string{"irccat", "thelounge", "ergo"} {
		if err := systemctl("stop", svc); err != nil {
			log.Printf("warning: stop %s failed: %v", svc, err)
		}
	}

	if err := backupErgoDB(cfg.ergoDB); err != nil {
		return err
	}

	if err := initErgoDB(cfg.ergoBin, cfg.ergoConf); err != nil {
		return err
	}

	if err := systemctl("start", "ergo"); err != nil {
		return err
	}

	return waitForErgo(cfg.ircHost, cfg.ircPort, 30*time.Second)
}

func backupErgoDB(path string) error {
	if _, err := os.Stat(path); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	backupPath := fmt.Sprintf("%s.backup.%d", path, time.Now().Unix())
	if err := os.Rename(path, backupPath); err != nil {
		return fmt.Errorf("backup db: %w", err)
	}
	return nil
}

func initErgoDB(ergoBin, confPath string) error {
	u, err := user.Lookup("ergo")
	if err != nil {
		return fmt.Errorf("lookup ergo user: %w", err)
	}
	uid, err := parseID(u.Uid)
	if err != nil {
		return err
	}
	gid, err := parseID(u.Gid)
	if err != nil {
		return err
	}
	cmd := exec.Command(ergoBin, "initdb", "--conf", confPath)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Credential: &syscall.Credential{Uid: uid, Gid: gid},
	}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("initdb failed: %w (%s)", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func parseID(raw string) (uint32, error) {
	var id uint64
	_, err := fmt.Sscanf(raw, "%d", &id)
	if err != nil {
		return 0, fmt.Errorf("parse id %q: %w", raw, err)
	}
	return uint32(id), nil
}

func systemctl(action, service string) error {
	cmd := exec.Command("systemctl", action, service)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl %s %s failed: %w (%s)", action, service, strings.TrimSpace(string(output)))
	}
	return nil
}

func registerUser(cfg config, operPassword, username, userPassword string) (string, error) {
	output, err := runNickServ(cfg, operPassword, username, userPassword, true)
	if err != nil {
		return "error", err
	}
	lower := strings.ToLower(output)
	if strings.Contains(lower, "successfully registered") {
		return "registered", nil
	}
	if strings.Contains(lower, "already registered") {
		return "already registered", nil
	}
	if strings.Contains(lower, "illegal") || strings.Contains(lower, "error") {
		return "error", fmt.Errorf("registration failed for %s", username)
	}
	return "completed (check logs)", nil
}

func unregisterUser(cfg config, operPassword, username string) (string, error) {
	output, err := runNickServ(cfg, operPassword, username, "", false)
	if err != nil {
		return "error", err
	}
	lower := strings.ToLower(output)
	if strings.Contains(lower, "dropped") {
		return "dropped", nil
	}
	if strings.Contains(lower, "unknown") {
		return "not found", nil
	}
	if strings.Contains(lower, "error") || strings.Contains(lower, "illegal") {
		return "error", fmt.Errorf("unregister failed for %s", username)
	}
	return "completed (check logs)", nil
}

func runNickServ(cfg config, operPassword, username, userPassword string, register bool) (string, error) {
	addr := fmt.Sprintf("%s:%d", cfg.ircHost, cfg.ircPort)
	conn, err := tls.Dial("tcp", addr, &tls.Config{InsecureSkipVerify: cfg.tlsInsecure, ServerName: cfg.ircHost})
	if err != nil {
		return "", fmt.Errorf("connect IRC: %w", err)
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(cfg.timeout))

	reader := bufio.NewReader(conn)
	var output strings.Builder
	readDone := make(chan struct{})
	go func() {
		for {
			line, err := reader.ReadString('\n')
			if len(line) > 0 {
				output.WriteString(line)
			}
			if err != nil {
				break
			}
		}
		close(readDone)
	}()

	sendLine := func(line string) {
		fmt.Fprintf(conn, "%s\r\n", line)
	}

	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
	botNick := fmt.Sprintf("OperBot%d", rnd.Intn(1000000))

	sendLine("NICK " + botNick)
	time.Sleep(1 * time.Second)
	sendLine("USER operbot 0 * :Operator Bot")
	time.Sleep(2 * time.Second)
	sendLine("OPER admin " + operPassword)
	time.Sleep(1 * time.Second)
	if register {
		sendLine(fmt.Sprintf("NS SAREGISTER %s %s %s@localhost", username, userPassword, username))
		time.Sleep(1 * time.Second)
		sendLine("QUIT :Registration complete")
	} else {
		sendLine(fmt.Sprintf("NS SADROP %s", username))
		time.Sleep(1 * time.Second)
		sendLine("QUIT :Unregistration complete")
	}

	select {
	case <-readDone:
	case <-time.After(cfg.timeout):
	}

	return output.String(), nil
}
