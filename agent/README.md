# AnalyzeBot Agent

A Genkit-powered IRC agent that connects to Ergo server and uses an MCP server for data access.

## Setup

1.  **Dependencies**: `npm install`
2.  **Configuration**: Copy `.env` and fill in details.
    ```env
    IRC_SERVER=chat.interestedparticipant.org
    IRC_PORT=6697
    IRC_NICK=AnalyzeBot
    IRC_CHANNEL=#analyze-this
    MCP_SERVER_URL=http://localhost:3000/sse
    GOOGLE_GENAI_API_KEY=your_api_key
    IRC_PASSWORD=your_irc_password (optional)
    ```
3.  **Build**: `npm run build`
4.  **Run**: `npm start`

## Features

- connects to IRC with TLS.
- Joins `#analyze-this`.
- Listens for messages addressing the bot.
- Uses Firebase MCP Server tools to answer user/item/worker queue questions.
- Powered by Google Genkit & Gemini 1.5 Flash.
