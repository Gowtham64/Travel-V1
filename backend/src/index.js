require("dotenv").config();
const express = require("express");
const cors = require("cors");
const tripRouter = require("./routes/trip");
const geocodeRouter = require("./routes/geocode");

const app = express();

app.use(cors());
app.use(express.json({ limit: "10mb" }));

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.use("/api/trip", tripRouter);
app.use("/api/geocode", geocodeRouter);

const PORT = process.env.PORT || 3000;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Travel app backend listening on http://localhost:${PORT}`);
  });
}

module.exports = app;
