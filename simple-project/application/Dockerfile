FROM golang:1.18-alpine

WORKDIR /app

COPY go.mod ./

COPY *.go ./

RUN go mod download

RUN go build -o /web

ENV BRANCH_NAME test

CMD [ "/web" ] 