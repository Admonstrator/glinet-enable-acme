# GitHub Workflows

This directory contains automated workflows for the glinet-enable-acme project.

## Workflows

### 🧪 `test-script.yaml`
**Triggers:** Push to main/develop, Pull Requests

Comprehensive testing suite that runs on every code change:

- **ShellCheck Analysis** - Linting and best practices
- **Syntax Validation** - Tests with dash, bash, and sh
- **Flag Parsing Tests** - Validates command line arguments
- **POSIX Compliance Check** - Ensures compatibility with ash/OpenWrt
- **Log Function Tests** - Tests ASCII and emoji modes
- **README Consistency** - Verifies all flags are documented
- **Integration Checks** - Validates all functions are defined

### 📊 `update-badges.yml`
**Triggers:** Weekly (Sunday at 00:00), Manual dispatch

Automatically updates README badges with current statistics:

- Fetches repository stars and forks from GitHub API
- Extracts script version from enable-acme.sh
- Generates readme.md from readme.template.md
- Commits changes if statistics have changed

## Local Testing

Test the script syntax locally:
```bash
sh -n enable-acme.sh
```

Run help flag test:
```bash
sh enable-acme.sh --help
```

## Template System

The badge workflow uses a template system:
- `readme.template.md` - Template with placeholder badges
- `readme.md` - Generated file (updated automatically)

**Note:** Edit `readme.template.md` for content changes, not `readme.md`!
