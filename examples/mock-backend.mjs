import http from "node:http";

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/v1/chat/completions") {
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
    return;
  }

  const chunks = [];

  req.on("data", (chunk) => {
    chunks.push(chunk);
  });

  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf8");
    console.log(`received payload bytes: ${body.length}`);

    res.writeHead(200, { "content-type": "application/json" });
    res.end(
      JSON.stringify({
        choices: [
          {
            message: {
              content: "mock transcription from local backend"
            }
          }
        ]
      })
    );
  });
});

server.listen(8787, () => {
  console.log("mock backend listening on http://127.0.0.1:8787/v1/chat/completions");
});
