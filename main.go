package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

var clients = make(map[*websocket.Conn]bool) // connected clients
var broadcast = make(chan Message)           // broadcast channel

var logstashServer = "ws://127.0.0.1:3232"

// Clients is a strct of connected clients
type Clients struct {
	Connected bool
	id        string
}

// LogstashMessage is the type received rom Logstash
type LogstashMessage struct {
	ReadyReplicas uint64
	Host          string
	Timestamp     string `json:"@timestamp"`
}

// Configure the upgrader
var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}




type readOp struct {
	key  int
	resp chan int
}
type writeOp struct {
	key  int
	val  int
	resp chan bool
}

// Message object
type Message struct {
	Email    string `json:"email"`
	Username string `json:"username"`
	Message  string `json:"message"`
}

// Metrics will collect metrics here!
var state = make(map[string]int)
var mutex = &sync.Mutex{}
var readOps uint64
var writeOps uint64

func main() {

	// Create a simple file server
	fs := http.FileServer(http.Dir("./public"))
	http.Handle("/", fs)

	// Configure websocket route
	http.HandleFunc("/ws", handleConnections)

	// Start listening for incoming chat messages
	go handleMessages()
	go handleTimeBot()

	go connectLogstash()

	// Start the server on localhost port 8000 and log any errors
	log.Println("http server started on :8000")
	err := http.ListenAndServe(":8000", nil)
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}

func connectLogstash() {
	c, _, err := websocket.DefaultDialer.Dial(logstashServer, nil)

	if err != nil {
		log.Fatal("dial:", err)
	}
	log.Println("Connected to logstash")
	defer c.Close()
	done := make(chan struct{})

	go func() {
		defer c.Close()
		defer close(done)
		for {
			var lm LogstashMessage
			if err := c.ReadJSON(&lm); err != nil {
				log.Println("ReadJSON error:", err)
			}
			log.Printf("recv: %+v", lm)
			logStashMsg := Message{
				Email:    "logstash",
				Username: "LogstashBot",
				Message:  fmt.Sprintf("%+v", lm)}
			broadcast <- logStashMsg
			atomic.AddUint64(&readOps, 1)
		}
	}()

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case t := <-ticker.C:
			err := c.WriteMessage(websocket.TextMessage, []byte(t.String()))
			if err != nil {
				log.Println("write:", err)
				return
			}
		}
	}
}

func handleTimeBot() {
	for {

		timeMsg := Message{
			Email:    "time",
			Username: "TimeBot",
			Message:  "Time: " + time.Now().Format("20060102150405") + " readOps: " + string(readOps)}
		broadcast <- timeMsg
		time.Sleep(60 * time.Second)
	}
}

func handleConnections(w http.ResponseWriter, r *http.Request) {
	// Upgrade initial GET request to a websocket
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Fatal(err)
	}
	// Make sure we close the connection when the function returns
	defer ws.Close()

	// Register our new client
	clients[ws] = true

	for {
		var msg Message
		// Read in a new message as JSON and map it to a Message object
		err := ws.ReadJSON(&msg)
		if err != nil {
			log.Printf("error: %v", err)
			delete(clients, ws)
			break
		}
		auditMsg := Message{
			Email:    "audit",
			Username: "AuditBot",
			Message:  "Time: " + time.Now().Format("20060102150405")}
		broadcast <- auditMsg

		// Send the newly received message to the broadcast channel
		broadcast <- msg

	}

}

func handleMessages() {
	for {
		// Grab the next message from the broadcast channel
		msg := <-broadcast
		// Send it out to every client that is currently connected
		for client := range clients {
			err := client.WriteJSON(msg)
			if err != nil {
				log.Printf("error: %+v", err)
				client.Close()
				delete(clients, client)
			}
		}
	}
}
