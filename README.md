# Thesis Tester Image

A Docker image for running Java tests in the thesis-llm grading service. This image can clone Java repositories, build them with Maven or Gradle, run tests, and return structured JSON results.

## 🚀 Features

- **Java 17 Support** - Full JDK and JRE environment
- **Build System Support** - Maven and Gradle with auto-detection
- **Git Integration** - Clone repositories and checkout specific commits
- **Network Tools** - curl, ping, and other utilities
- **Security** - Runs as non-root user with resource limits
- **JSON Output** - Structured test results via stdout
- **Timeout Protection** - Configurable execution timeouts

## 📋 Prerequisites

- Docker installed and running
- Access to container registry (GitHub Container Registry recommended)
- Java test repository for testing

## 🔨 Building the Image

### Quick Build

```bash
# Build with default settings
docker build -t thesis-tester:latest .
```

### Automated Build and Push

```bash
# Make scripts executable
chmod +x build-and-push.sh test-local.sh

# Build and optionally push to registry
./build-and-push.sh ghcr.io/your-username latest
```

## 🧪 Testing Locally

### Test with Sample Repository

```bash
# Test with a public Java repository
./test-local.sh https://github.com/junit-team/junit4.git

# Test with specific commit
./test-local.sh https://github.com/your-repo/java-project.git abc123def

# Test with custom image tag
./test-local.sh https://github.com/your-repo/java-project.git HEAD thesis-tester:dev
```

### Manual Testing

```bash
# Run container manually
docker run --rm \
  -e GRADING_JOB_ID=123 \
  -e REPO_URL="https://github.com/junit-team/junit4.git" \
  -e GIT_COMMIT_HASH="HEAD" \
  -e OUTPUT_FORMAT="json" \
  -e TIMEOUT_SECONDS=300 \
  thesis-tester:latest
```

## 🔧 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GRADING_JOB_ID` | Unique job identifier | `unknown` |
| `REPO_URL` | Git repository URL | Required |
| `GIT_COMMIT_HASH` | Specific commit to checkout | `HEAD` |
| `OUTPUT_FORMAT` | Output format (json) | `json` |
| `TIMEOUT_SECONDS` | Maximum execution time | `300` |

## 📊 Output Format

The image outputs structured JSON to stdout:

```json
{
  "gradingJobId": 123,
  "status": "COMPLETED",
  "startedAt": "2024-01-01T10:00:00Z",
  "completedAt": "2024-01-01T10:05:00Z",
  "testResults": [
    {
      "testName": "testAddition",
      "className": "CalculatorTest",
      "passed": true,
      "output": "",
      "durationMs": 150
    }
  ],
  "compilationOutput": "BUILD SUCCESS",
  "errorMessage": null,
  "exitCode": 0,
  "executionLogs": [
    {
      "type": "INFO",
      "message": "Starting test execution",
      "timestamp": "2024-01-01T10:00:00Z"
    }
  ]
}
```

## 🏗️ Supported Build Systems

### Maven Projects

- Automatically detected by `pom.xml`
- Commands: `mvn clean compile test-compile test`
- Test reports: `target/surefire-reports/TEST-*.xml`

### Gradle Projects

- Automatically detected by `build.gradle` or `build.gradle.kts`
- Commands: `gradle clean compileJava compileTestJava test`
- Test reports: `build/test-results/test/TEST-*.xml`
- Supports both `gradle` command and `./gradlew` wrapper

## 🔐 Security Features

- **Non-root user** - Runs as `tester` user (UID 1000)
- **Resource limits** - CPU and memory constraints in Kubernetes
- **Read-only filesystem** - Where possible
- **Minimal attack surface** - Alpine-based with only necessary tools

## 🚀 Integration with thesis-llm

### 1. Update Configuration

```yaml
# In thesis-llm/k8s/configmap.yaml
tester-image: "ghcr.io/your-username/thesis-tester:latest"
```

### 2. Deploy Updated Configuration

```bash
kubectl apply -f thesis-llm/k8s/configmap.yaml
kubectl rollout restart deployment/llm-grading-service -n my-thesis
```

### 3. Monitor Job Execution

```bash
# Watch for jobs being created
kubectl get jobs -n my-thesis -w

# Check job logs
kubectl logs job/grading-job-XXX -n my-thesis
```

## 🛠️ Development

### Project Structure

```bash
thesis-tester/
├── Dockerfile              # Container definition
├── test-runner.sh          # Main execution script
├── test-local.sh          # Local testing script
├── build-and-push.sh      # Build automation
└── README.md              # This file
```

### Customizing the Image

#### Adding New Build Systems

1. Update `detect_build_system()` function
2. Add new build and test functions
3. Update the main execution flow

#### Modifying Test Parsing

1. Update `parse_*_test_results()` functions
2. Ensure output matches expected JSON schema

### Debugging

#### Container Logs

```bash
# Check stderr logs (execution logs)
docker run thesis-tester:latest 2>&1 | grep "\[ERROR\]"

# Get full container output
docker run thesis-tester:latest > output.json 2> logs.txt
```

#### Health Check

```bash
# Verify tools are installed
docker run --rm thesis-tester:latest java -version
docker run --rm thesis-tester:latest mvn -version
docker run --rm thesis-tester:latest gradle -version
```

## 📝 Troubleshooting

### Common Issues

#### Build Failures

- **Permission denied**: Check file permissions and user context
- **Network timeout**: Increase `TIMEOUT_SECONDS` value
- **Missing dependencies**: Verify build system configuration

#### Test Parsing Issues

- **No test results**: Check if tests are actually running
- **Incorrect JSON**: Verify XML report format and parsing logic
- **Missing test files**: Ensure build generates test reports

#### Container Issues

- **Image won't start**: Check Dockerfile syntax and base image
- **Script not found**: Verify `test-runner.sh` is copied and executable
- **Resource limits**: Adjust memory/CPU limits in Kubernetes

### Support

For issues related to:

- **Container building**: Check Docker logs and Dockerfile
- **Test execution**: Review `test-runner.sh` and add debug logging
- **Integration**: Verify thesis-llm configuration and logs

## 🎯 Performance Tuning

### Optimization Tips

- Use specific base image tags for reproducibility
- Minimize layer count in Dockerfile
- Set appropriate resource limits
- Use multi-stage builds to reduce image size

### Resource Recommendations

- **Memory**: 256Mi - 512Mi
- **CPU**: 100m - 300m
- **Timeout**: 300-600 seconds depending on project size

## 📄 License

This project is part of the thesis-llm grading service infrastructure.
