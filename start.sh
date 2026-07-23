#!/bin/bash
# OFSAA Scenario Debugger — Server Start Script
# Usage: ./start.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
mkdir -p logs

echo "Starting backend on port 8000..."
nohup bash -c "cd $APP_DIR/backend && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000" > logs/backend.log 2>&1 &
BACKEND_PID=$!
echo "  Backend PID: $BACKEND_PID"

echo "Starting frontend on port 3000..."
nohup bash -c "cd $APP_DIR/frontend-next && source \$HOME/.nvm/nvm.sh && nvm use 20 && npm run start" > logs/frontend.log 2>&1 &
FRONTEND_PID=$!
echo "  Frontend PID: $FRONTEND_PID"

echo ""
echo "Done. Open: http://192.168.3.32:3000"
echo "  Logs: $APP_DIR/logs/"
echo "  Admin / changeme123"
