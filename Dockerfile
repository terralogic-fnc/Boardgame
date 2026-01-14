# ==============================
# Stage 1: Build
# =========================
FROM maven:3.9.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Copy project
COPY . .

# (Optional debug – remove later)
RUN find . -name pom.xml

# Build (NO broken line continuations)
RUN cd workspace/* && mvn clean package -DskipTests


# =========================
# Stage 2: Runtime
# =========================
FROM eclipse-temurin:11-jre

WORKDIR /usr/src/app

# Copy the built JAR
COPY --from=builder /build/workspace/*/target/*.jar app.jar

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
