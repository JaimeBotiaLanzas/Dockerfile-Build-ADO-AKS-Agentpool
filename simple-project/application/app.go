package main

import (
	"net/http"
	"os"
	"fmt"
)

func indexHandler(w http.ResponseWriter, r *http.Request) {
	branch_name := os.Getenv("BRANCH_NAME")
	if branch_name == "" {
		branch_name = "There is no branch name!"
	}
	fmt.Fprintf(w, "Status: %s!", branch_name)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", indexHandler)
	http.ListenAndServe(":"+port, mux)
}