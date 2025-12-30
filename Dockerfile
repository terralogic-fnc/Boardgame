# ========================= # Stage 1: Build # =========================
FROM maven:3.9.9-eclipse-temurin-11 AS builder
WORKDIR /build 
# Copy entire Jenkins context 
COPY . .
# DEBUG (keep once, remove later) 
RUN find . -name pom.xml
# Build using shell so glob EXPANDS correctly
RUN cd workspace/* && \ ls -l &&
\ mvn clean install -DskipTests
# ========================= # Stage 2: Runtime # ========================= 
FROM eclipse-temurin:11-jre WORKDIR /usr/src/app 
# Copy jar from real project directory 
COPY --from=builder /build/workspace/*/target/*.jar app.jar 
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
