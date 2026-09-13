#!/usr/bin/env bash
# Runs the test suite. Fast tests (unit) run by default; pass --all to also
# run slow tests (integration, requires Docker for Testcontainers) and the
# frontend suite.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

run_backend_unit() {
  echo "==> Backend unit tests (fast)"
  dotnet test app/backend/tests/MovieOps.UnitTests --collect:"XPlat Code Coverage"
}

run_backend_integration() {
  echo "==> Backend integration tests (slow, needs Docker)"
  dotnet test app/backend/tests/MovieOps.IntegrationTests
}

run_frontend() {
  echo "==> Frontend unit tests"
  npm --prefix app/frontend test -- --watch=false
}

run_backend_unit

if [[ "${1:-}" == "--all" ]]; then
  run_backend_integration
  run_frontend
fi
