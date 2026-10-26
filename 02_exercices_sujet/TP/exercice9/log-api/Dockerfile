FROM maven:3.9.11-eclipse-temurin-21-alpine AS build

WORKDIR /app

# Copie d'abord le POM pour profiter du cache des dépendances Maven.
COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

EXPOSE 8081

ENTRYPOINT ["java", "-jar", "app.jar"]
