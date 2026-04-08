const express = require("express");
const mongoose = require("mongoose");
const fs = require("fs");

const app = express();
app.use(express.json());

const mongoUri = process.env.MONGO_URI;
if (!mongoUri) {
  throw new Error("MONGO_URI is not set");
}

mongoose.connect(mongoUri);

const Item = mongoose.model("Item", new mongoose.Schema({
  name: { type: String, required: true }
}));

app.get("/", async (_req, res) => {
  res.send(`
    <html>
      <body>
        <h1>Wiz Exercise App</h1>
        <p>API endpoints:</p>
        <ul>
          <li>GET /items</li>
          <li>POST /items { "name": "test" }</li>
          <li>GET /wizexercise</li>
        </ul>
      </body>
    </html>
  `);
});

app.get("/wizexercise", (_req, res) => {
  const content = fs.readFileSync("/app/wizexercise.txt", "utf8");
  res.type("text/plain").send(content);
});

app.post("/items", async (req, res) => {
  const item = await Item.create({ name: req.body.name });
  res.status(201).json(item);
});

app.get("/items", async (_req, res) => {
  const items = await Item.find().lean();
  res.json(items);
});

app.listen(3000, () => {
  console.log("Listening on :3000");
});
