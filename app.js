import { ethers } from "./vendor/ethers.min.js";
import { CONFIG } from "./config.js";

const ABI = [
  "function setBio(string bio)",
  "function tip(string handle, string message) payable",
  "function tipToken(string handle, address token, uint256 amount, string message)",
  "function profileOf(string handle) view returns (bool registered, uint32 tips, string bio)",
  "function totalTips() view returns (uint256)",
  "function recipientCount() view returns (uint256)",
  "function tipperCount() view returns (uint256)",
  "function getRecipients(uint256 start, uint256 count) view returns ((string handle,uint32 tipsReceived,uint256 receivedNative,uint256 receivedTokenA,uint256 receivedTokenB)[])",
  "function getTippers(uint256 start, uint256 count) view returns ((address tipper,string handle,uint32 tipsSent,uint32 uniqueRecipients,uint256 sentNative,uint256 sentTokenA,uint256 sentTokenB)[])",
  "event Tipped(bytes32 indexed labelhash, address indexed from, address indexed token, address to, uint256 amount, string toHandle, string fromHandle, string message)",
];
const REG_ABI = ["function handleOf(address) view returns (string)"];
const ERC20_ABI = [
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function balanceOf(address) view returns (uint256)",
];

const $ = (id) => document.getElementById(id);
const read = new ethers.JsonRpcProvider(CONFIG.READ_RPC, CONFIG.CHAIN_ID, { staticNetwork: true });
const kudosR = new ethers.Contract(CONFIG.CONTRACT, ABI, read);
const regR = new ethers.Contract(CONFIG.REGISTRY, REG_ABI, read);
let signer = null, account = null, myHandle = "";

const HANDLE_RE = /^[a-z0-9]{3,20}$/;
const clean = (s) => s.trim().toLowerCase().replace(/\.ai$/, "");
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const fmt = (v) => Number(ethers.formatUnits(v, 18)).toLocaleString(undefined, { maximumFractionDigits: 6 });
const tokenName = (addr) => Object.entries(CONFIG.TOKENS).find(([, t]) => t.address.toLowerCase() === addr.toLowerCase())?.[0] ?? "?";
function status(el, msg, cls = "") { $(el).innerHTML = `<p class="${cls}">${msg}</p>`; }

$("contractLink").href = `${CONFIG.EXPLORER}/address/${CONFIG.CONTRACT}#code`;

// ---- wallet: injected provider only, no QR / pairing codes, no sessions stored anywhere
async function connect() {
  if (!window.ethereum) { alert("No browser wallet found. Install or open this page in a wallet browser."); return; }
  const bp = new ethers.BrowserProvider(window.ethereum);
  await bp.send("eth_requestAccounts", []);
  const net = await bp.getNetwork();
  if (Number(net.chainId) !== CONFIG.CHAIN_ID) {
    try { await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CONFIG.CHAIN_HEX }] }); }
    catch { alert("Please switch your wallet to BSC (chain 56)."); return; }
  }
  signer = await new ethers.BrowserProvider(window.ethereum).getSigner();
  account = await signer.getAddress();
  myHandle = await regR.handleOf(account).catch(() => "");
  $("connect").textContent = myHandle ? `${myHandle}.ai` : short(account);
  $("me").innerHTML = myHandle ? `Connected as <b>${esc(myHandle)}.ai</b>` : `Connected ${short(account)} (no Agent ID, you can still tip)`;
  $("myHandle").textContent = myHandle || "your name";
  if (myHandle) {
    const link = `${location.origin}${location.pathname}#to=${myHandle}`;
    $("shareLink").innerHTML = `Share your tip link: <a href="${esc(link)}">${esc(link)}</a>`;
  }
}
window.ethereum?.on?.("accountsChanged", () => location.reload());
window.ethereum?.on?.("chainChanged", () => location.reload());
$("connect").onclick = connect;

// ---- recipient lookup (shows name, tip count and bio only; never the recipient's address)
let lookupTimer;
async function lookup() {
  const h = clean($("to").value);
  if (!h) { $("jarInfo").textContent = ""; return; }
  if (!HANDLE_RE.test(h)) { $("jarInfo").textContent = "Names are 3–20 lowercase letters or digits."; return; }
  try {
    const p = await kudosR.profileOf(h);
    $("jarInfo").innerHTML = p.registered
      ? `<span class="ok">✓ ${esc(h)}.ai</span> · ${p.tips} kudos received${p.bio ? ` · “${esc(p.bio)}”` : ""}`
      : `<span class="err">${esc(h)}.ai is not a registered Agent ID.</span>`;
  } catch (e) { $("jarInfo").textContent = "Could not read the jar (network)."; }
}
$("to").addEventListener("input", () => { clearTimeout(lookupTimer); lookupTimer = setTimeout(lookup, 350); });

async function sendTip() {
  try {
    if (!signer) await connect();
    if (!signer) return;
    const h = clean($("to").value);
    const msg = $("message").value;
    const sym = $("token").value;
    const t = CONFIG.TOKENS[sym];
    if (!HANDLE_RE.test(h)) return status("tipStatus", "Enter a valid .ai name.", "err");
    if (new TextEncoder().encode(msg).length > 280) return status("tipStatus", "Message is longer than 280 bytes.", "err");
    const amount = ethers.parseUnits(String($("amount").value || "0"), t.decimals);
    if (amount <= 0n) return status("tipStatus", "Enter an amount.", "err");
    const p = await kudosR.profileOf(h);
    if (!p.registered) return status("tipStatus", `${esc(h)}.ai is not a registered Agent ID.`, "err");
    if (!confirm(`Send ${$("amount").value} ${sym} to ${h}.ai?\nYour wallet will ask you to confirm.`)) return;
    const kudos = new ethers.Contract(CONFIG.CONTRACT, ABI, signer);
    let tx;
    if (sym === "BNB") {
      status("tipStatus", "Confirm the tip in your wallet…");
      tx = await kudos.tip(h, msg, { value: amount });
    } else {
      const erc = new ethers.Contract(t.address, ERC20_ABI, signer);
      if ((await erc.balanceOf(account)) < amount) return status("tipStatus", `Not enough ${sym}.`, "err");
      const allowance = await erc.allowance(account, CONFIG.CONTRACT);
      if (allowance < amount) {
        status("tipStatus", `Step 1/2: approve exactly ${$("amount").value} ${sym} in your wallet…`);
        await (await erc.approve(CONFIG.CONTRACT, amount)).wait();
      }
      status("tipStatus", "Step 2/2: confirm the tip in your wallet…");
      tx = await kudos.tipToken(h, t.address, amount, msg);
    }
    status("tipStatus", `Sent, waiting for confirmation… <a target="_blank" href="${CONFIG.EXPLORER}/tx/${tx.hash}">view</a>`);
    await tx.wait();
    status("tipStatus", `✓ Kudos delivered to ${esc(h)}.ai · <a target="_blank" href="${CONFIG.EXPLORER}/tx/${tx.hash}">BscScan</a>`, "ok");
    loadBoards(); lookup();
  } catch (e) { status("tipStatus", esc(e.shortMessage || e.message), "err"); }
}
$("sendTip").onclick = sendTip;

async function jarAction(fn, label) {
  try {
    if (!signer) await connect();
    if (!signer) return;
    if (!myHandle) return status("jarStatus", "This wallet holds no Agent ID.", "err");
    const kudos = new ethers.Contract(CONFIG.CONTRACT, ABI, signer);
    status("jarStatus", `Confirm "${label}" in your wallet…`);
    const tx = await fn(kudos);
    await tx.wait();
    status("jarStatus", `✓ ${label} done · <a target="_blank" href="${CONFIG.EXPLORER}/tx/${tx.hash}">BscScan</a>`, "ok");
    loadBoards();
  } catch (e) { status("jarStatus", esc(e.shortMessage || e.message), "err"); }
}
$("setBio").onclick = () => jarAction((k) => k.setBio($("bio").value), "Save bio");

// ---- leaderboards straight from contract storage (no indexer, no server)
async function loadAll(fn, total) {
  const out = []; const page = 200;
  for (let i = 0; i < total; i += page) out.push(...(await fn(i, page)));
  return out;
}
const usdValue = (a, b) => Number(ethers.formatUnits(a + b, 18));
async function loadBoards() {
  try {
    const [tt, tj, tc] = await Promise.all([kudosR.totalTips(), kudosR.recipientCount(), kudosR.tipperCount()]);
    $("stats").innerHTML = `<div><b>${tt}</b>kudos sent</div><div><b>${tj}</b>names tipped</div><div><b>${tc}</b>tippers</div>`;
    const jars = await loadAll((s, c) => kudosR.getRecipients(s, c), Number(tj));
    jars.sort((a, b) => Number(b.tipsReceived) - Number(a.tipsReceived));
    $("topJars").innerHTML = jars.slice(0, 15).map((j) =>
      `<li><a href="#to=${esc(j.handle)}">${esc(j.handle)}.ai</a> · ${j.tipsReceived} kudos · ${fmt(j.receivedNative)} BNB · $${usdValue(j.receivedTokenA, j.receivedTokenB).toFixed(2)}</li>`).join("") || "<li class=muted>No kudos yet</li>";
    const tippers = (await loadAll((s, c) => kudosR.getTippers(s, c), Number(tc))).filter((t) => t.handle);
    tippers.sort((a, b) => Number(b.uniqueRecipients) - Number(a.uniqueRecipients) || Number(b.tipsSent) - Number(a.tipsSent));
    $("topTippers").innerHTML = tippers.slice(0, 15).map((t) =>
      `<li>${esc(t.handle)}.ai · ${t.tipsSent} kudos to ${t.uniqueRecipients} names</li>`).join("") || "<li class=muted>No tippers yet</li>";
  } catch (e) { $("stats").textContent = "Contract not reachable yet."; }
  loadFeed();
}
async function loadFeed() {
  try {
    const latest = await read.getBlockNumber();
    const from = Math.max(CONFIG.DEPLOY_BLOCK || 0, latest - 49000);
    const logs = await kudosR.queryFilter(kudosR.filters.Tipped(), from, latest);
    $("feed").innerHTML = logs.slice(-25).reverse().map((l) => {
      const a = l.args; const who = a.fromHandle ? `${esc(a.fromHandle)}.ai` : short(a.from);
      return `<li><b>${who}</b> → <b>${esc(a.toHandle)}.ai</b>: ${fmt(a.amount)} ${tokenName(a.token)}${a.message ? ` · “${esc(a.message)}”` : ""} <a class="small" target="_blank" href="${CONFIG.EXPLORER}/tx/${l.transactionHash}">tx</a></li>`;
    }).join("") || "<li class=muted>No kudos in the last ~6 hours</li>";
  } catch { $("feed").innerHTML = "<li class=muted>Feed unavailable</li>"; }
}

function fromHash() {
  const m = location.hash.match(/to=([a-z0-9.]+)/i);
  if (m) { $("to").value = clean(m[1]); lookup(); document.getElementById("tip").scrollIntoView(); }
}
window.addEventListener("hashchange", fromHash);
fromHash();
loadBoards();
