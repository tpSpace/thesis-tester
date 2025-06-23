# Multi-stage build for Java tester image
FROM eclipse-temurin:17-jdk-alpine AS builder

# Install build tools and dependencies
RUN apk add --no-cache \
    git \
    curl \
    wget \
    bash \
    findutils \
    grep \
    sed \
    tar \
    gzip \
    jq \
    unzip

# Install Maven
ENV MAVEN_VERSION=3.9.6
ENV MAVEN_HOME=/opt/maven
RUN wget https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz && \
    tar -xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt && \
    mv /opt/apache-maven-${MAVEN_VERSION} ${MAVEN_HOME} && \
    rm apache-maven-${MAVEN_VERSION}-bin.tar.gz

# Install Gradle
ENV GRADLE_VERSION=8.5
ENV GRADLE_HOME=/opt/gradle
RUN wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip && \
    unzip gradle-${GRADLE_VERSION}-bin.zip -d /opt && \
    mv /opt/gradle-${GRADLE_VERSION} ${GRADLE_HOME} && \
    rm gradle-${GRADLE_VERSION}-bin.zip

# Production stage
FROM eclipse-temurin:17-jdk-alpine

# Install system tools and utilities
RUN apk add --no-cache \
    git \
    curl \
    wget \
    bash \
    findutils \
    grep \
    sed \
    tar \
    gzip \
    unzip \
    openssh-client \
    ca-certificates \
    iputils-ping \
    net-tools \
    procps \
    jq \
    && rm -rf /var/cache/apk/*

# Copy build tools from builder stage
COPY --from=builder /opt/maven /opt/maven
COPY --from=builder /opt/gradle /opt/gradle

# Set up PATH for Maven and Gradle
ENV PATH="/opt/maven/bin:/opt/gradle/bin:${PATH}"
ENV MAVEN_HOME=/opt/maven
ENV GRADLE_HOME=/opt/gradle

# Create working directories and user
RUN mkdir -p /workspace /results /logs && \
    addgroup -g 1000 tester && \
    adduser -D -u 1000 -G tester tester && \
    chown -R tester:tester /workspace /results /logs

# Copy test runner script (will be created next)
COPY test-runner.sh /usr/local/bin/test-runner.sh
RUN chmod +x /usr/local/bin/test-runner.sh

# Switch to non-root user for security
USER tester

# Set working directory
WORKDIR /workspace

# Environment variables for configuration
ENV GRADING_JOB_ID=""
ENV REPO_URL=""
ENV GIT_COMMIT_HASH="HEAD"
ENV OUTPUT_FORMAT="json"
ENV TIMEOUT_SECONDS="300"

# Health check to verify the container is ready
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=2 \
    CMD java -version && mvn -version && gradle -version || exit 1

# Default command
CMD ["/usr/local/bin/test-runner.sh"]