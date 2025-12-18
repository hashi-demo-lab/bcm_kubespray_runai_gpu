# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Note**: This project uses AGENTS.md files for detailed guidance. 

## Primary Reference

Please see the root `./AGENTS.md` in this same directory for the main project documentation and guidance. 

@/workspace/AGENTS.md


## Additional Component-Specific Guidance

For detailed module-specific implementation guides, also check for AGENTS.md files in subdirectories throughout the project

These component-specific AGENTS.md files contain targeted guidance for working with those particular areas of the codebase.

If you need to ask the user a question use the tool AskUserQuestion this is useful during speckit.clarify

## Updating AGENTS.md Files

When you discover new information that would be helpful for future development work, please:

- **Update existing AGENTS.md files** when you learn implementation details, debugging insights, or architectural patterns specific to that component
- **Create new AGENTS.md files** in relevant directories when working with areas that don't yet have documentation
- **Add valuable insights** such as common pitfalls, debugging techniques, dependency relationships, or implementation patterns

## Important use subagents liberally

When performing any research concurrent subagents can be used for performance and isolation
use parrallel tool calls and tasks where possible
- !/bin/bash
HOST="15.197.150.161"
PORT="443"

echo "=== Basic connectivity ==="
nc -zv $HOST $PORT 2>&1

echo -e "\n=== TLS Certificate ==="
echo | openssl s_client -connect $HOST:$PORT 2>/dev/null | openssl x509 -noout -text | head -20

echo -e "\n=== TLS Handshake Details ==="
echo | openssl s_client -connect $HOST:$PORT -state 2>&1 | grep -E "(SSL_connect|alert|error)"

echo -e "\n=== Client Cert Request? ==="
echo | openssl s_client -connect $HOST:$PORT 2>&1 | grep -A5 "Acceptable client"

echo -e "\n=== Supported TLS Versions ==="
for v in tls1_1 tls1_2 tls1_3; do
  echo -n "$v: "
  timeout 5 openssl s_client -connect $HOST:$PORT -$v 2>&1 | grep -q "CONNECTED" && echo "OK" || echo "FAIL"
done