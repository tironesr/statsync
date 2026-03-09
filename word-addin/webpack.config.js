const path = require("path");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const CopyWebpackPlugin = require("copy-webpack-plugin");

module.exports = async (env, options) => {
  const dev = options.mode === "development";

  // Only load and use dev certs during local development
  let httpsOptions = {};
  if (dev) {
    const devCerts = require("office-addin-dev-certs");
    httpsOptions = await devCerts.getHttpsServerOptions();
  }

  return {
    entry: {
      taskpane: "./src/taskpane/taskpane.ts",
      dialog: "./src/dialog/dialog.ts",
    },
    output: {
      path: path.resolve(__dirname, "dist"),
      filename: "[name].js",
      clean: true,
    },
    resolve: {
      extensions: [".ts", ".js"],
    },
    module: {
      rules: [
        {
          test: /\.ts$/,
          use: "ts-loader",
          exclude: /node_modules/,
        },
        {
          test: /\.css$/,
          use: ["style-loader", "css-loader"],
        },
      ],
    },
    plugins: [
      new HtmlWebpackPlugin({
        template: "./src/taskpane/taskpane.html",
        filename: "taskpane.html",
        chunks: ["taskpane"],
      }),
      new HtmlWebpackPlugin({
        template: "./src/dialog/dialog.html",
        filename: "dialog.html",
        chunks: ["dialog"],
      }),
      new CopyWebpackPlugin({
        patterns: [
          {
            from: "src/assets",
            to: "assets",
            noErrorOnMissing: true,
          },
          {
            from: "src/sw.js",
            to: "sw.js",
          },
        ],
      }),
    ],
    devServer: {
      static: {
        directory: path.join(__dirname, "dist"),
      },
      headers: {
        "Access-Control-Allow-Origin": "*",
      },
      server: {
        type: "https",
        options: httpsOptions,
      },
      port: 3000,
      hot: true,
    },
    devtool: dev ? "source-map" : false,
  };
};