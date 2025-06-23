#!/bin/bash

# Java Test Runner Script for LLM Grading Service
# Communicates with thesis-llm via stdout JSON

set -euo pipefail

# Configuration from environment variables
GRADING_JOB_ID="${GRADING_JOB_ID:-unknown}"
REPO_URL="${REPO_URL:-}"
GIT_COMMIT_HASH="${GIT_COMMIT_HASH:-HEAD}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"

# Working directories
WORKSPACE_DIR="/workspace"
REPO_DIR="${WORKSPACE_DIR}/repo"

# Global variables for result tracking
START_TIME=""
TEST_RESULTS="[]"
EXECUTION_LOGS="[]"
COMPILATION_OUTPUT=""
ERROR_MESSAGE=""
EXIT_CODE=0
EXTRACTED_CODE=""
CODE_FILES="[]"

# Logging function that also adds to execution logs
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date -Iseconds)
    
    # Log to stderr for container logs (won't interfere with stdout JSON)
    echo "[${timestamp}] [$level] $message" >&2
    
    # Add to execution logs JSON array
    local log_entry=$(jq -n \
        --arg type "$level" \
        --arg message "$message" \
        --arg timestamp "$timestamp" \
        '{type: $type, message: $message, timestamp: $timestamp}')
    
    EXECUTION_LOGS=$(echo "$EXECUTION_LOGS" | jq ". += [$log_entry]")
}

# Error handler
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    
    log "ERROR" "$message"
    ERROR_MESSAGE="$message"
    EXIT_CODE="$exit_code"
    
    output_final_result
    exit "$exit_code"
}

# Output final JSON result to stdout
output_final_result() {
    local status="COMPLETED"
    if [[ $EXIT_CODE -ne 0 ]]; then
        status="FAILED"
    fi
    
    local completed_at=$(date -Iseconds)
    
    # Log detailed results before outputting JSON
    log_detailed_results "$status"
    
    # Build the final result JSON
    jq -n \
        --arg gradingJobId "$GRADING_JOB_ID" \
        --arg status "$status" \
        --arg startedAt "$START_TIME" \
        --arg completedAt "$completed_at" \
        --argjson testResults "$TEST_RESULTS" \
        --arg compilationOutput "$COMPILATION_OUTPUT" \
        --arg errorMessage "$ERROR_MESSAGE" \
        --arg exitCode "$EXIT_CODE" \
        --argjson executionLogs "$EXECUTION_LOGS" \
        --arg extractedCode "$EXTRACTED_CODE" \
        --argjson codeFiles "$CODE_FILES" \
        '{
            gradingJobId: ($gradingJobId | tonumber),
            status: $status,
            startedAt: $startedAt,
            completedAt: $completedAt,
            testResults: $testResults,
            compilationOutput: $compilationOutput,
            errorMessage: ($errorMessage | if . == "" then null else . end),
            exitCode: ($exitCode | tonumber),
            executionLogs: $executionLogs,
            extractedCode: ($extractedCode | if . == "" then null else . end),
            codeFiles: $codeFiles
        }'
}

# Extract student code from repository
extract_student_code() {
    log "INFO" "Extracting student code from repository"
    cd "$REPO_DIR"
    
    local code_files="[]"
    local main_code=""
    
    # Find all Java source files (excluding test files)
    local java_files
    java_files=$(find . -name "*.java" -type f | grep -v -i test | head -10) # Limit to 10 files to avoid huge output
    
    if [[ -n "$java_files" ]]; then
        while IFS= read -r file_path; do
            if [[ -f "$file_path" ]]; then
                local file_name=$(basename "$file_path")
                local relative_path="${file_path#./}"
                local file_content
                
                # Read file content (limit to reasonable size)
                if file_content=$(head -c 10000 "$file_path" 2>/dev/null); then
                    log "INFO" "Extracted code from: $relative_path (${#file_content} characters)"
                    
                    # Create code file JSON object
                    local code_file
                    code_file=$(jq -n \
                        --arg fileName "$file_name" \
                        --arg filePath "$relative_path" \
                        --arg content "$file_content" \
                        --arg size "${#file_content}" \
                        '{
                            fileName: $fileName,
                            filePath: $filePath,
                            content: $content,
                            size: ($size | tonumber)
                        }')
                    
                    code_files=$(echo "$code_files" | jq ". += [$code_file]")
                    
                    # If this looks like the main implementation file, save it as main code
                    if [[ "$file_name" != *"Test"* ]] && [[ "$file_name" != *"test"* ]] && [[ -z "$main_code" ]]; then
                        main_code="$file_content"
                    fi
                fi
            fi
        done <<< "$java_files"
    fi
    
    # Set global variables
    CODE_FILES="$code_files"
    EXTRACTED_CODE="$main_code"
    
    # Log the extracted code in execution logs
    if [[ -n "$main_code" ]]; then
        log "INFO" "Main student code extracted (${#main_code} characters)"
        log "CODE" "```java
$main_code
```"
    else
        log "WARNING" "No main student code found"
    fi
    
    log "INFO" "Code extraction completed - found $(echo "$code_files" | jq 'length') files"
}

# Log detailed results for debugging
log_detailed_results() {
    local status="$1"
    
    log "INFO" "=================== DETAILED TEST RESULTS ==================="
    log "INFO" "Grading Job ID: $GRADING_JOB_ID"
    log "INFO" "Status: $status"
    log "INFO" "Repository: $REPO_URL"
    log "INFO" "Commit: $GIT_COMMIT_HASH"
    log "INFO" "Started: $START_TIME"
    log "INFO" "Completed: $(date -Iseconds)"
    
    # Log test results in detail
    local test_count
    test_count=$(echo "$TEST_RESULTS" | jq 'length')
    log "INFO" "Total tests executed: $test_count"
    
    if [[ $test_count -gt 0 ]]; then
        local passed_count
        local failed_count
        passed_count=$(echo "$TEST_RESULTS" | jq '[.[] | select(.passed == true)] | length')
        failed_count=$(echo "$TEST_RESULTS" | jq '[.[] | select(.passed == false)] | length')
        
        log "INFO" "Tests passed: $passed_count"
        log "INFO" "Tests failed: $failed_count"
        
        # Log individual test results
        echo "$TEST_RESULTS" | jq -r '.[] | "Test: \(.testName) - Passed: \(.passed) - Output: \(.output // "No output") - Error: \(.errorOutput // "No error")"' | while IFS= read -r line; do
            log "TEST_RESULT" "$line"
        done
    fi
    
    # Log compilation output if available
    if [[ -n "$COMPILATION_OUTPUT" ]]; then
        log "COMPILATION" "Compilation output:"
        log "COMPILATION" "$COMPILATION_OUTPUT"
    fi
    
    # Log code files found
    local code_file_count
    code_file_count=$(echo "$CODE_FILES" | jq 'length')
    log "INFO" "Code files extracted: $code_file_count"
    
    if [[ $code_file_count -gt 0 ]]; then
        echo "$CODE_FILES" | jq -r '.[] | "File: \(.filePath) (\(.size) bytes)"' | while IFS= read -r line; do
            log "CODE_FILE" "$line"
        done
    fi
    
    # Log error message if present
    if [[ -n "$ERROR_MESSAGE" ]]; then
        log "ERROR" "Error message: $ERROR_MESSAGE"
    fi
    
    log "INFO" "=================== END DETAILED RESULTS ==================="
}

# Detect build system
detect_build_system() {
    if [[ -f "$REPO_DIR/pom.xml" ]]; then
        echo "maven"
    elif [[ -f "$REPO_DIR/build.gradle" ]] || [[ -f "$REPO_DIR/build.gradle.kts" ]]; then
        echo "gradle"
    elif [[ -f "$REPO_DIR/Makefile" ]]; then
        echo "make"
    else
        # Check for Java files - if we find .java files, use plain Java compilation
        local java_files
        java_files=$(find "$REPO_DIR" -name "*.java" 2>/dev/null | head -1)
        if [[ -n "$java_files" ]]; then
            echo "plain-java"
        else
            echo "unknown"
        fi
    fi
}

# Clone repository
clone_repository() {
    log "INFO" "Cloning repository: $REPO_URL"
    
    if [[ -z "$REPO_URL" ]]; then
        error_exit "REPO_URL environment variable is required"
    fi
    
    # Create repo directory
    mkdir -p "$REPO_DIR"
    
    # Clone with timeout
    if ! timeout "$TIMEOUT_SECONDS" git clone "$REPO_URL" "$REPO_DIR"; then
        error_exit "Failed to clone repository within ${TIMEOUT_SECONDS} seconds"
    fi
    
    # Checkout specific commit if provided
    if [[ "$GIT_COMMIT_HASH" != "HEAD" ]]; then
        log "INFO" "Checking out commit: $GIT_COMMIT_HASH"
        cd "$REPO_DIR"
        if ! git checkout "$GIT_COMMIT_HASH"; then
            error_exit "Failed to checkout commit: $GIT_COMMIT_HASH"
        fi
    fi
    
    log "INFO" "Repository cloned successfully"
}

# Build with Maven
build_maven() {
    log "INFO" "Building with Maven"
    cd "$REPO_DIR"
    
    # Clean and compile
    if ! COMPILATION_OUTPUT=$(mvn clean compile test-compile 2>&1); then
        log "ERROR" "Maven compilation failed"
        error_exit "Compilation failed" 2
    fi
    
    log "INFO" "Maven build successful"
}

# Build with Gradle
build_gradle() {
    log "INFO" "Building with Gradle"
    cd "$REPO_DIR"
    
    # Make gradlew executable if it exists
    if [[ -f "./gradlew" ]]; then
        chmod +x ./gradlew
        GRADLE_CMD="./gradlew"
    else
        GRADLE_CMD="gradle"
    fi
    
    # Clean and build
    if ! COMPILATION_OUTPUT=$($GRADLE_CMD clean compileJava compileTestJava 2>&1); then
        log "ERROR" "Gradle compilation failed"
        error_exit "Compilation failed" 2
    fi
    
    log "INFO" "Gradle build successful"
}

# Build plain Java files
build_plain_java() {
    log "INFO" "Building plain Java files"
    cd "$REPO_DIR"
    
    # Find all Java files
    local java_files
    java_files=$(find . -name "*.java" -type f)
    
    if [[ -z "$java_files" ]]; then
        error_exit "No Java files found in repository"
    fi
    
    log "INFO" "Found Java files: $(echo "$java_files" | tr '\n' ' ')"
    
    # Create a classes directory for compiled output
    mkdir -p classes
    
    # Compile all Java files
    if ! COMPILATION_OUTPUT=$(javac -d classes $java_files 2>&1); then
        log "ERROR" "Java compilation failed"
        log "ERROR" "Compilation output: $COMPILATION_OUTPUT"
        error_exit "Compilation failed" 2
    fi
    
    log "INFO" "Plain Java compilation successful"
}

# Run Maven tests and parse results
run_maven_tests() {
    log "INFO" "Running Maven tests"
    cd "$REPO_DIR"
    
    # Run tests (don't fail on test failures)
    local test_output
    test_output=$(mvn test -Dmaven.test.failure.ignore=true 2>&1) || true
    
    # Parse test results from Maven Surefire reports
    parse_maven_test_results
    
    log "INFO" "Maven tests completed"
}

# Run Gradle tests and parse results
run_gradle_tests() {
    log "INFO" "Running Gradle tests"
    cd "$REPO_DIR"
    
    # Determine Gradle command
    local gradle_cmd="gradle"
    if [[ -f "./gradlew" ]]; then
        gradle_cmd="./gradlew"
    fi
    
    # Run tests (continue on test failures)
    local test_output
    test_output=$($gradle_cmd test --continue 2>&1) || true
    
    # Parse test results from Gradle test reports
    parse_gradle_test_results
    
    log "INFO" "Gradle tests completed"
}

# Run plain Java tests
run_plain_java_tests() {
    log "INFO" "Running plain Java tests"
    cd "$REPO_DIR"
    
    # Find test classes (classes that contain "Test" in their name or have test methods)
    local test_classes=()
    local compiled_classes
    compiled_classes=$(find classes -name "*.class" -type f | sed 's/classes\///g' | sed 's/\.class$//g' | tr '/' '.')
    
    # Look for classes that look like test classes
    for class_name in $compiled_classes; do
        local java_file=$(find . -name "*.java" -exec grep -l "class.*$class_name" {} \;)
        if [[ -n "$java_file" ]] && (grep -q "test\|Test\|TEST" "$java_file" || [[ "$class_name" == *"Test"* ]] || [[ "$class_name" == *"Tester"* ]]); then
            test_classes+=("$class_name")
        fi
    done
    
    if [[ ${#test_classes[@]} -eq 0 ]]; then
        log "WARNING" "No test classes found, looking for main methods"
        # If no test classes, try to find classes with main methods
        for class_name in $compiled_classes; do
            local java_file=$(find . -name "*.java" -exec grep -l "class.*$class_name" {} \;)
            if [[ -n "$java_file" ]] && grep -q "public static void main" "$java_file"; then
                test_classes+=("$class_name")
            fi
        done
    fi
    
    if [[ ${#test_classes[@]} -eq 0 ]]; then
        log "WARNING" "No test classes or main methods found, running all classes"
        test_classes=($compiled_classes)
    fi
    
    log "INFO" "Running test classes: ${test_classes[*]}"
    
    # Run each test class and collect results
    local results="[]"
    for class_name in "${test_classes[@]}"; do
        log "INFO" "Running test class: $class_name"
        
        local output=""
        local error_output=""
        local passed="true"
        local exit_code=0
        
        # Try to run the class
        if output=$(timeout 30 java -cp classes "$class_name" 2>&1); then
            log "INFO" "Test class $class_name executed successfully"
            log "TEST_OUTPUT" "Output from $class_name: $output"
            if echo "$output" | grep -iq "fail\|error\|exception"; then
                passed="false"
                error_output="$output"
                log "TEST_FAILED" "Test $class_name failed with output: $output"
            else
                log "TEST_PASSED" "Test $class_name passed with output: $output"
            fi
        else
            exit_code=$?
            passed="false"
            error_output="Test class execution failed with exit code $exit_code: $(timeout 30 java -cp classes "$class_name" 2>&1 || echo "Failed to capture error output")"
            if [[ $exit_code -eq 124 ]]; then
                error_output="Test class execution timed out (30 seconds)"
            fi
            log "WARNING" "Test class $class_name failed: $error_output"
        fi
        
        # Create test result JSON object (thesis-llm schema compliant)
        local test_result
        test_result=$(jq -n \
            --arg testName "$class_name" \
            --argjson passed "$passed" \
            --arg output "$output" \
            --arg errorOutput "$error_output" \
            '{
                testName: $testName,
                passed: $passed,
                output: $output,
                errorOutput: ($errorOutput | if . == "" then null else . end),
                durationMs: null
            }')
        
        results=$(echo "$results" | jq ". += [$test_result]")
    done
    
    TEST_RESULTS="$results"
    log "INFO" "Plain Java tests completed"
}

# Parse Maven test results from XML reports
parse_maven_test_results() {
    local results="[]"
    
    if [[ -d "target/surefire-reports" ]]; then
        # Find XML test result files
        local xml_files
        xml_files=$(find target/surefire-reports -name "TEST-*.xml" 2>/dev/null || true)
        
        if [[ -n "$xml_files" ]]; then
            while IFS= read -r xml_file; do
                if [[ -f "$xml_file" ]]; then
                    # Process each test case
                    while IFS= read -r testcase_line; do
                        if [[ -n "$testcase_line" ]]; then
                            local test_name
                            test_name=$(echo "$testcase_line" | sed 's/.*name="\([^"]*\)".*/\1/')
                            
                            local passed="true"
                            local output="Test passed"
                            local error_output=""
                            
                            # Check if test failed
                            if grep -A 10 "testcase.*name=\"$test_name\"" "$xml_file" | grep -q "failure\|error"; then
                                passed="false"
                                output="Test failed"
                                error_output=$(grep -A 5 "failure\|error" "$xml_file" | head -1 | sed 's/<[^>]*>//g' || echo "Test failed")
                            fi
                            
                            # Create test result JSON object (thesis-llm schema compliant)
                            local test_result
                            test_result=$(jq -n \
                                --arg testName "$test_name" \
                                --argjson passed "$passed" \
                                --arg output "$output" \
                                --arg errorOutput "$error_output" \
                                '{
                                    testName: $testName,
                                    passed: $passed,
                                    output: $output,
                                    errorOutput: ($errorOutput | if . == "" then null else . end),
                                    durationMs: null
                                }')
                            
                            results=$(echo "$results" | jq ". += [$test_result]")
                        fi
                    done < <(grep -o 'testcase.*name="[^"]*"' "$xml_file" || true)
                fi
            done <<< "$xml_files"
        fi
    fi
    
    TEST_RESULTS="$results"
}

# Parse Gradle test results from XML reports  
parse_gradle_test_results() {
    local results="[]"
    
    if [[ -d "build/test-results/test" ]]; then
        # Find XML test result files
        local xml_files
        xml_files=$(find build/test-results/test -name "TEST-*.xml" 2>/dev/null || true)
        
        if [[ -n "$xml_files" ]]; then
            while IFS= read -r xml_file; do
                if [[ -f "$xml_file" ]]; then
                    # Process each test case
                    while IFS= read -r testcase_line; do
                        if [[ -n "$testcase_line" ]]; then
                            local test_name
                            test_name=$(echo "$testcase_line" | sed 's/.*name="\([^"]*\)".*/\1/')
                            
                            local passed="true"
                            local output="Test passed"
                            local error_output=""
                            
                            # Check if test failed
                            if grep -A 10 "testcase.*name=\"$test_name\"" "$xml_file" | grep -q "failure\|error"; then
                                passed="false"
                                output="Test failed"
                                error_output=$(grep -A 5 "failure\|error" "$xml_file" | head -1 | sed 's/<[^>]*>//g' || echo "Test failed")
                            fi
                            
                            # Create test result JSON object (thesis-llm schema compliant)
                            local test_result
                            test_result=$(jq -n \
                                --arg testName "$test_name" \
                                --argjson passed "$passed" \
                                --arg output "$output" \
                                --arg errorOutput "$error_output" \
                                '{
                                    testName: $testName,
                                    passed: $passed,
                                    output: $output,
                                    errorOutput: ($errorOutput | if . == "" then null else . end),
                                    durationMs: null
                                }')
                            
                            results=$(echo "$results" | jq ". += [$test_result]")
                        fi
                    done < <(grep -o 'testcase.*name="[^"]*"' "$xml_file" || true)
                fi
            done <<< "$xml_files"
        fi
    fi
    
    TEST_RESULTS="$results"
}

# Main execution
main() {
    START_TIME=$(date -Iseconds)
    
    log "INFO" "Starting test runner for grading job: $GRADING_JOB_ID"
    log "INFO" "Repository: $REPO_URL"
    log "INFO" "Commit: $GIT_COMMIT_HASH"
    
    # Step 1: Clone repository
    clone_repository
    
    # Step 2: Extract student code
    extract_student_code
    
    # Step 3: Detect build system
    local build_system
    build_system=$(detect_build_system)
    log "INFO" "Detected build system: $build_system"
    
    # Step 4: Build project
    case "$build_system" in
        maven)
            build_maven
            ;;
        gradle)
            build_gradle
            ;;
        plain-java)
            build_plain_java
            ;;
        *)
            error_exit "Unsupported build system: $build_system"
            ;;
    esac
    
    # Step 5: Run tests
    case "$build_system" in
        maven)
            run_maven_tests
            ;;
        gradle)
            run_gradle_tests
            ;;
        plain-java)
            run_plain_java_tests
            ;;
    esac
    
    log "INFO" "Test execution completed successfully"
    
    # Output final results to stdout for thesis-llm to read
    output_final_result
}

# Trap signals for graceful shutdown
trap 'error_exit "Test runner interrupted" 130' INT TERM

# Run main function
main "$@"