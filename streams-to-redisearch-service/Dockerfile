FROM redisdeveloper/rmdb-streams-to-redis-hashes:1.0.0

ENV REDIS_HOST=redis-service
ENV REDIS_PORT=6379
ENV REDIS_PASSWORD=

EXPOSE 8085
ENTRYPOINT ["java","-jar","/app.jar","--spring.profiles.active=prod"]


