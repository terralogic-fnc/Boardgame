# =========================
# Stage 1: Build
# =========================
FROM maven:3.9.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy entire Jenkins context
COPY . .

# Go into the real Jenkins job workspace
# This folder name = Jenkins JOB_NAME
WORKDIR /build/workspace/${JOB_NAME}

# Debug once (remove later)
RUN ls -l && test -f pom.xml

# Build
RUN mvn clean install -DskipTests

# =========================
# Stage 2: Runtime
# =========================
FROM eclipse-temurin:11-jre

ENV APP_HOME=/usr/src/app
WORKDIR $APP_HOME

COPY --from=builder /build/workspace/${JOB_NAME}/target/*.jar app.jar

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
