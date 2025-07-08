FROM redisdeveloper/rmdb-comments:1.0.0

ENV  REDIS_HOST=redis-service
ENV  REDIS_PORT=6379
ENV  REDIS_PASSWORD=

EXPOSE 8086

CMD [ "node", "server.js", "--CONF_FILE", "./config.prod.json" ]
