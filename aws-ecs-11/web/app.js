// setup.sh replaces the API URL token from settings.local.sh before uploading.
const API_URL = "__API_URL__";

async function callApi() {
  const result = document.getElementById("result");

  result.textContent = "通信中...";

  try {
    const response = await fetch(API_URL);

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json();
    result.innerHTML = `
      <strong>${data.title}</strong><br>
      ${data.message}
      ${
        data.accessCount !== null
          ? `<br><small>Access Count: ${data.accessCount}</small>`
          : ""
      }
    `;
  } catch (error) {
    console.error(error);
    result.textContent = "API接続失敗";
  }
}
