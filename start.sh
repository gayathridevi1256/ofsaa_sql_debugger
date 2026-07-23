#!/bin/bash
# OFSAA Scenario Debugger — Server Start Script
# Usage: ./start.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
mkdir -p logs

echo "Starting backend on port 8000..."
nohup bash -c "cd $APP_DIR/backend && source \$HOME/.bashrc 2>/dev/null; uv run uvicorn app.main:app --host 0.0.0.0 --port 8000" > logs/backend.log 2>&1 &
echo "  Backend PID: $!"

echo "Starting frontend on port 3000..."
nohup bash -c "cd $APP_DIR/frontend-next && source \$HOME/.nvm/nvm.sh && nvm use 20 && npm run start" > logs/frontend.log 2>&1 &
echo "  Frontend PID: $!"

sleep 2
echo ""
echo "Backend : http://192.168.3.32:8000/docs"
echo "Frontend: http://192.168.3.32:3000"
echo "Logs    : $APP_DIR/logs/"
echo "Login   : admin / changeme123"
