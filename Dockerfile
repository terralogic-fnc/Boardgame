# =========================
# Stage 1: Build
# =========================
FROM maven:3.9.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy pom.xml first (for better cache + correctness)
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline

# Copy rest of the source code
COPY src ./src

# Build the application
RUN mvn clean install -DskipTests

# =========================
# Stage 2: Runtime
# =========================
FROM eclipse-temurin:11-jre

ENV APP_HOME=/usr/src/app
WORKDIR $APP_HOME

# Copy only the built JAR
COPY --from=builder /build/target/*.jar app.jar

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
