const api = document.body.dataset.api;
const tbody = document.getElementById("orders");
const message = document.getElementById("message");

async function loadOrders() {
  const res = await fetch(`${api}/orders?limit=20`);
  if (!res.ok) { message.textContent = `Failed to load orders (${res.status})`; return; }
  const orders = await res.json();
  tbody.replaceChildren(...orders.map((o) => {
    const tr = document.createElement("tr");
    for (const v of [o.id, o.item, o.quantity, o.status]) {
      const td = document.createElement("td");
      td.textContent = v; // textContent, never innerHTML: no XSS from order data
      tr.appendChild(td);
    }
    tr.className = o.status.toLowerCase();
    return tr;
  }));
}

document.getElementById("order-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = new FormData(e.target);
  const res = await fetch(`${api}/orders`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ item: form.get("item"), quantity: Number(form.get("quantity")) }),
  });
  message.textContent = res.ok ? "Order placed" : `Order failed (${res.status})`;
  if (res.ok) e.target.reset();
  loadOrders();
});

loadOrders();
setInterval(loadOrders, 3000); // watch the worker flip PENDING -> PROCESSED
