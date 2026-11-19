import { ethers } from "./vendor/ethers.min.js";
import { CONFIG } from "./config.js";

// ---------------------------------------------------------------- ABIs
const KUDOS_ABI = [
  "function tip(string handle, string message) payable",
  "function tipToken(string handle, address token, uint256 amount, string message)",
  "function setBio(string bio)",
  "function profileOf(string handle) view returns (bool registered, uint32 tips, string bio)",
  "function received(bytes32, address) view returns (uint256)",
  "function totalTips() view returns (uint256)",
  "function recipientCount() view returns (uint256)",
  "function tipperCount() view returns (uint256)",
  "function getRecipients(uint256 start, uint256 count) view returns ((string handle,uint32 tipsReceived,uint256 receivedNative,uint256 receivedTokenA,uint256 receivedTokenB)[])",
  "function getTippers(uint256 start, uint256 count) view returns ((address tipper,string handle,uint32 tipsSent,uint32 uniqueRecipients,uint256 sentNative,uint256 sentTokenA,uint256 sentTokenB)[])",
  "event Tipped(bytes32 indexed labelhash, address indexed from, address indexed token, address to, uint256 amount, string toHandle, string fromHandle, string message)",
];
const CARD_ABI = [
  "function mint()",
  "function gm()",
  "function gm(string to)",
  "function totalSupply() view returns (uint256)",
  "function totalGm() view returns (uint256)",
  "function gmCount() view returns (uint256)",
  "function canGmToday(address) view returns (bool)",
  "function statsOf(string handle) view returns ((string handle,bool hasCard,uint32 lastDay,uint32 streak,uint32 best,uint32 total,uint32 shoutsSent,uint32 shoutsReceived))",
  "function getGmStats(uint256 start, uint256 count) view returns ((string handle,bool hasCard,uint32 lastDay,uint32 streak,uint32 best,uint32 total,uint32 shoutsSent,uint32 shoutsReceived)[])",
  "function getCards(uint256 start, uint256 count) view returns (string[])",
  "function tokenURI(uint256) view returns (string)",
  "event CardMinted(bytes32 indexed labelhash, address indexed holder, string handle)",
  "event GmSaid(bytes32 indexed labelhash, address indexed account, uint32 day, uint32 streak, uint32 total, string handle)",
  "event Shoutout(bytes32 indexed fromLabel, bytes32 indexed toLabel, string fromHandle, string toHandle)",
];
const REG_ABI = ["function handleOf(address) view returns (string)", "function ownerOfHandle(string) view returns (address)"];
const ERC20_ABI = ["function allowance(address,address) view returns (uint256)", "function approve(address,uint256) returns (bool)", "function balanceOf(address) view returns (uint256)"];

// ---------------------------------------------------------------- setup
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const read = new ethers.JsonRpcProvider(CONFIG.READ_RPC, CONFIG.CHAIN_ID, { staticNetwork: true, batchMaxCount: 10 });
const kudosR = new ethers.Contract(CONFIG.CONTRACT, KUDOS_ABI, read);
const regR = new ethers.Contract(CONFIG.REGISTRY, REG_ABI, read);
const CARD_LIVE = /^0x[0-9a-fA-F]{40}$/.test(CONFIG.CARD || "");
const cardR = CARD_LIVE ? new ethers.Contract(CONFIG.CARD, CARD_ABI, read) : null;

const HANDLE_RE = /^[a-z0-9]{3,20}$/;
const clean = (s) => String(s || "").trim().toLowerCase().replace(/^@/, "").replace(/\.ai$/, "");
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const fmt = (v, d = 18) => Number(ethers.formatUnits(v, d)).toLocaleString(undefined, { maximumFractionDigits: 6 });
const tokenName = (addr) => Object.entries(CONFIG.TOKENS).find(([, t]) => t.address.toLowerCase() === addr.toLowerCase())?.[0] ?? "?";
const hlink = (h) => `<a class="h" href="#/${esc(h)}">${esc(h)}.ai</a>`;

let wallet = { provider: null, signer: null, account: null, handle: "" };
let cache = { recipients: [], tippers: [], gms: [], feed: [] };
let token = "BNB";

$("#kLink").href = `${CONFIG.EXPLORER}/address/${CONFIG.CONTRACT}#code`;
$("#repoLink").href = CONFIG.REPO;
if (CARD_LIVE) $("#cLink").href = `${CONFIG.EXPLORER}/address/${CONFIG.CARD}#code`;
else { $("#cLink").textContent = "Card contract (coming soon)"; $("#cLink").removeAttribute("href"); }
if (!CARD_LIVE) $$(".card-soon").forEach((e) => e.classList.remove("hidden"));

// ---------------------------------------------------------------- ui helpers
function toast(html, kind = "", ms = 6000) {
  const t = document.createElement("div");
  t.className = `toast ${kind}`; t.innerHTML = html;
  $("#toasts").appendChild(t);
  setTimeout(() => t.remove(), ms);
}
function review(title, rows, okLabel = "Open wallet to confirm") {
  return new Promise((resolve) => {
    $("#sheetTitle").textContent = title;
    $("#sheetBody").innerHTML = rows.map(([k, v]) => `<div class="kv"><span>${esc(k)}</span><b>${v}</b></div>`).join("") +
      `<p class="fine">Nothing is sent until you confirm in your wallet. You can still reject it there.</p>`;
    $("#sheetOk").textContent = okLabel;
    $("#sheet").classList.remove("hidden");
    const done = (v) => { $("#sheet").classList.add("hidden"); $("#sheetOk").onclick = $("#sheetCancel").onclick = null; resolve(v); };
    $("#sheetOk").onclick = () => done(true);
    $("#sheetCancel").onclick = () => done(false);
  });
}
function countUp(el, to) {
  const from = Number(el.dataset.v || 0); el.dataset.v = to;
  if (from === to) { el.textContent = to.toLocaleString(); return; }
  const t0 = performance.now(), dur = 900;
  const step = (t) => { const p = Math.min(1, (t - t0) / dur); el.textContent = Math.round(from + (to - from) * (1 - Math.pow(1 - p, 3))).toLocaleString(); if (p < 1) requestAnimationFrame(step); };
  requestAnimationFrame(step);
}
const txLink = (h) => `<a target="_blank" rel="noopener" href="${CONFIG.EXPLORER}/tx/${h}">view tx</a>`;
const errMsg = (e) => esc(e?.shortMessage || e?.info?.error?.message || e?.reason || e?.message || "Transaction failed").slice(0, 220);

// ---------------------------------------------------------------- wallet (EIP-1193 / EIP-6963 only)
const discovered = [];
window.addEventListener("eip6963:announceProvider", (e) => { if (!discovered.find((d) => d.info.uuid === e.detail.info.uuid)) discovered.push(e.detail); });
window.dispatchEvent(new Event("eip6963:requestProvider"));

function pickProvider() {
  if (discovered.length === 1) return discovered[0].provider;
  if (discovered.length > 1) {
    const bn = discovered.find((d) => /binance/i.test(d.info.name));
    return (window.ethereum && discovered.some((d) => d.provider === window.ethereum)) ? window.ethereum : (bn || discovered[0]).provider;
  }
  return window.ethereum || window.binancew3w?.ethereum || null;
}
async function ensureChain(p) {
  const id = await p.request({ method: "eth_chainId" });
  if (parseInt(id, 16) === CONFIG.CHAIN_ID) return;
  try { await p.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CONFIG.CHAIN_HEX }] }); }
  catch (e) {
    if (e?.code === 4902) {
      await p.request({ method: "wallet_addEthereumChain", params: [{ chainId: CONFIG.CHAIN_HEX, chainName: "BNB Smart Chain", nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 }, rpcUrls: ["https://bsc-dataseed.bnbchain.org"], blockExplorerUrls: [CONFIG.EXPLORER] }] });
    } else throw e;
  }
}
async function connect() {
  const p = pickProvider();
  if (!p) { toast("No wallet found. Open this page in the Binance Web3 Wallet browser, MetaMask or another wallet app.", "err", 8000); return false; }
  try {
    await p.request({ method: "eth_requestAccounts" });
    await ensureChain(p);
    const bp = new ethers.BrowserProvider(p);
    wallet.provider = p; wallet.signer = await bp.getSigner(); wallet.account = await wallet.signer.getAddress();
    wallet.handle = await regR.handleOf(wallet.account).catch(() => "");
    p.on?.("accountsChanged", () => location.reload());
    p.on?.("chainChanged", () => location.reload());
    renderMe();
    return true;
  } catch (e) { toast(errMsg(e), "err"); return false; }
}
async function needWallet() {
  if (wallet.signer) {
    try { await ensureChain(wallet.provider); wallet.signer = await new ethers.BrowserProvider(wallet.provider).getSigner(); } catch (e) { toast(errMsg(e), "err"); return false; }
    return true;
  }
  return connect();
}
$("#connect").onclick = () => (wallet.account ? (location.hash = wallet.handle ? `#/${wallet.handle}` : "#/") : connect());

function renderMe() {
  $("#connect").textContent = wallet.handle ? `${wallet.handle}.ai` : short(wallet.account);
  const b = $("#meBanner");
  b.classList.remove("hidden");
  b.innerHTML = wallet.handle
    ? `👋 gm <b>${esc(wallet.handle)}.ai</b>. Share your tip link: <a class="grad" href="#/${esc(wallet.handle)}">${esc(location.origin + location.pathname)}#/${esc(wallet.handle)}</a>`
    : `Connected ${short(wallet.account)}. This wallet holds no Agent ID: you can still tip, but cards and gm need a .ai name (claim one in the Binance App → Wallet → Agent ID).`;
  refreshGm(); refreshCard();
}

// ---------------------------------------------------------------- tx runner
async function runTx(label, fn) {
  try {
    const tx = await fn();
    toast(`⏳ ${esc(label)} submitted · ${txLink(tx.hash)}`, "", 9000);
    await tx.wait();
    toast(`✅ ${esc(label)} confirmed · ${txLink(tx.hash)}`, "ok", 9000);
    setTimeout(loadAll, 1500);
    return true;
  } catch (e) {
    if (e?.code === "ACTION_REJECTED" || e?.code === 4001) toast("Cancelled in wallet.", "", 4000);
    else toast(errMsg(e), "err", 9000);
    return false;
  }
}

// ---------------------------------------------------------------- name check (never shows addresses)
async function checkName(h, el) {
  if (!h) { el.innerHTML = ""; return false; }
  if (!HANDLE_RE.test(h)) { el.innerHTML = `<span class="err">Names are 3–20 lowercase letters or digits.</span>`; return false; }
  try {
    const p = await kudosR.profileOf(h);
    el.innerHTML = p.registered
      ? `<span class="ok">✓ ${esc(h)}.ai</span> <span class="muted">· ${p.tips} kudos received${p.bio ? ` · “${esc(p.bio)}”` : ""}</span>`
      : `<span class="err">${esc(h)}.ai is not a registered Agent ID.</span>`;
    return p.registered;
  } catch { el.innerHTML = `<span class="muted">Could not check this name right now.</span>`; return false; }
}
function debounceCheck(input, info) {
  let t; input.addEventListener("input", () => { clearTimeout(t); t = setTimeout(() => checkName(clean(input.value), info), 350); });
}
debounceCheck($("#to"), $("#toInfo"));
debounceCheck($("#gmTo"), $("#gmToInfo"));

// ---------------------------------------------------------------- tip
$$("#tokenSeg button").forEach((b) => (b.onclick = () => { token = b.dataset.tok; $$("#tokenSeg button").forEach((x) => x.classList.toggle("on", x === b)); }));
$$("#quick button").forEach((b) => (b.onclick = () => { $("#amount").value = b.dataset.amt; }));
$("#sendTip").onclick = async () => {
  const h = clean($("#to").value), msg = $("#message").value, t = CONFIG.TOKENS[token];
  if (!(await checkName(h, $("#toInfo")))) return toast("Enter a registered .ai name.", "err");
  if (new TextEncoder().encode(msg).length > 280) return toast("Message is longer than 280 bytes.", "err");
  let amount; try { amount = ethers.parseUnits(String($("#amount").value || "0"), t.decimals); } catch { amount = 0n; }
  if (amount <= 0n) return toast("Enter an amount.", "err");
  if (!(await needWallet())) return;
  if (wallet.handle === h) return toast("You can't tip yourself.", "err");
  const rows = [["To", `${esc(h)}.ai`], ["Amount", `${esc($("#amount").value)} ${token}`], ["Message", msg ? esc(msg) : "<span class='muted'>none</span>"], ["Contract", "AgentKudos (non-custodial)"]];
  if (token !== "BNB") rows.push(["Steps", `1. approve exactly ${esc($("#amount").value)} ${token} · 2. tip`]);
  if (!(await review("Review tip", rows))) return;
  const kudos = new ethers.Contract(CONFIG.CONTRACT, KUDOS_ABI, wallet.signer);
  if (token === "BNB") return runTx(`Tip to ${h}.ai`, () => kudos.tip(h, msg, { value: amount }));
  const erc = new ethers.Contract(t.address, ERC20_ABI, wallet.signer);
  if ((await erc.balanceOf(wallet.account)) < amount) return toast(`Not enough ${token}.`, "err");
  if ((await erc.allowance(wallet.account, CONFIG.CONTRACT)) < amount) {
    const ok = await runTx(`Approve ${$("#amount").value} ${token}`, () => erc.approve(CONFIG.CONTRACT, amount));
    if (!ok) return;
  }
  runTx(`Tip to ${h}.ai`, () => kudos.tipToken(h, t.address, amount, msg));
};

// ---------------------------------------------------------------- gm
function resetCountdown() {
  const now = Date.now(), next = Math.ceil((now + 1) / 86400000) * 86400000, s = Math.floor((next - now) / 1000);
  $("#resetIn").textContent = `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}
setInterval(resetCountdown, 30000); resetCountdown();
async function refreshGm() {
  const btn = $("#sayGm");
  if (!CARD_LIVE) { btn.disabled = true; btn.textContent = "gm opens soon"; return; }
  if (!wallet.handle) { ["#myStreak", "#myBest", "#myTotal"].forEach((s) => ($(s).textContent = "–")); btn.disabled = false; btn.textContent = wallet.account ? "Needs an Agent ID" : "Connect & say gm"; return; }
  try {
    const [s, can] = await Promise.all([cardR.statsOf(wallet.handle), cardR.canGmToday(wallet.account)]);
    $("#myStreak").textContent = s.streak; $("#myBest").textContent = s.best; $("#myTotal").textContent = s.total;
    btn.disabled = !can; btn.textContent = can ? "Say gm ☀️" : "gm done today ✓ come back tomorrow";
  } catch { /* ignore */ }
}
$("#sayGm").onclick = async () => {
  if (!CARD_LIVE) return;
  if (!(await needWallet())) return;
  if (!wallet.handle) return toast("gm is for Agent ID holders. Claim your .ai in the Binance App → Wallet → Agent ID.", "err", 8000);
  const to = clean($("#gmTo").value);
  if (to) {
    if (to === wallet.handle) return toast("Shout out someone else 🙂", "err");
    if (!(await checkName(to, $("#gmToInfo")))) return toast("That .ai is not registered.", "err");
  }
  if (!(await review("Say gm", [["From", `${esc(wallet.handle)}.ai`], ["Shout-out", to ? `${esc(to)}.ai` : "<span class='muted'>none</span>"], ["Value", "0 (gas only)"]]))) return;
  const card = new ethers.Contract(CONFIG.CARD, CARD_ABI, wallet.signer);
  const ok = await runTx("gm", () => (to ? card["gm(string)"](to) : card["gm()"]()));
  if (ok) refreshGm();
};

// ---------------------------------------------------------------- card
function svgFromURI(uri) {
  try { const j = JSON.parse(atob(uri.split(",")[1])); return { image: j.image, attrs: j.attributes }; } catch { return null; }
}
async function refreshCard() {
  const btn = $("#mintCard"), hint = $("#cardHint");
  if (!CARD_LIVE) { btn.disabled = true; btn.textContent = "Claiming opens soon"; hint.textContent = "The card contract is being deployed. Your card will be free (gas only)."; return; }
  if (!wallet.account) { btn.disabled = false; btn.textContent = "Connect & claim"; hint.textContent = "One per Agent ID. Gas only."; return; }
  if (!wallet.handle) { btn.disabled = true; btn.textContent = "Needs an Agent ID"; hint.textContent = "Claim your .ai in the Binance App → Wallet → Agent ID first."; return; }
  try {
    const s = await cardR.statsOf(wallet.handle);
    if (s.hasCard) {
      const id = BigInt(ethers.id(wallet.handle));
      const d = svgFromURI(await cardR.tokenURI(id));
      if (d) $("#myCard").src = d.image;
      btn.disabled = true; btn.textContent = "Card claimed ✓"; hint.innerHTML = `Your card updates live with every gm and kudos. <a class="grad" href="#/${esc(wallet.handle)}">View profile</a>`;
    } else { btn.disabled = false; btn.textContent = `Claim ${wallet.handle}.ai card`; hint.textContent = "Soulbound, free, gas only."; }
  } catch { /* ignore */ }
}
$("#mintCard").onclick = async () => {
  if (!CARD_LIVE) return;
  if (!(await needWallet())) return;
  if (!wallet.handle) return refreshCard();
  if (!(await review("Claim Kudos Card", [["Card", `${esc(wallet.handle)}.ai`], ["Type", "Soulbound (non-transferable)"], ["Value", "0 (gas only)"]]))) return;
  const card = new ethers.Contract(CONFIG.CARD, CARD_ABI, wallet.signer);
  if (await runTx("Card claim", () => card.mint())) refreshCard();
};

// ---------------------------------------------------------------- data loading
async function pageAll(fn, total, page = 200) {
  const out = []; for (let i = 0; i < total; i += page) out.push(...(await fn(i, page))); return out;
}
async function loadStats() {
  const safe = (pr, d) => pr.catch((e) => { console.warn(e); return d; });
  const [tt, rc, tc] = await Promise.all([safe(kudosR.totalTips(), 0n), safe(kudosR.recipientCount(), 0n), safe(kudosR.tipperCount(), 0n)]);
  countUp($('[data-stat="tips"]'), Number(tt));
  const gmEl = $('[data-stat="gm"]'), cEl = $('[data-stat="cards"]');
  if (CARD_LIVE) {
    const [g, n, supply] = await Promise.all([safe(cardR.totalGm(), 0n), safe(cardR.gmCount(), 0n), safe(cardR.totalSupply(), 0n)]);
    countUp(gmEl, Number(g)); countUp(cEl, Number(supply));
    cache.gms = await safe(pageAll((s, c) => cardR.getGmStats(s, c), Number(n)), cache.gms);
  } else { gmEl.textContent = "soon"; cEl.textContent = "soon"; }
  cache.recipients = await safe(pageAll((s, c) => kudosR.getRecipients(s, c), Number(rc)), cache.recipients);
  cache.tippers = await safe(pageAll((s, c) => kudosR.getTippers(s, c), Number(tc)), cache.tippers);
  const users = new Set();
  cache.tippers.forEach((t) => t.handle && users.add(t.handle));
  cache.gms.forEach((g) => g.total > 0 && users.add(g.handle));
  countUp($('[data-stat="users"]'), users.size);
}
async function logsChunked(contract, filter, from) {
  const latest = await read.getBlockNumber();
  const start = Math.max(from || 0, latest - 98000);
  const ranges = []; for (let a = start; a <= latest; a += 49000) ranges.push([a, Math.min(latest, a + 48999)]);
  const res = await Promise.all(ranges.map(([a, b]) => contract.queryFilter(filter, a, b).catch(() => [])));
  return res.flat();
}
async function loadFeed() {
  const items = [];
  const tips = await logsChunked(kudosR, kudosR.filters.Tipped(), CONFIG.DEPLOY_BLOCK);
  tips.forEach((l) => { const a = l.args; items.push({ b: l.blockNumber, i: l.index, tx: l.transactionHash, ic: "⚡", from: a.fromHandle, fromAddr: a.from, to: a.toHandle,
    html: `${a.fromHandle ? hlink(a.fromHandle) : `<b>${short(a.from)}</b>`} tipped ${hlink(a.toHandle)} <b>${fmt(a.amount)} ${tokenName(a.token)}</b>${a.message ? `<div class="msg">“${esc(a.message)}”</div>` : ""}` }); });
  if (CARD_LIVE) {
    const [gms, shouts, mints] = await Promise.all([
      logsChunked(cardR, cardR.filters.GmSaid(), CONFIG.CARD_DEPLOY_BLOCK),
      logsChunked(cardR, cardR.filters.Shoutout(), CONFIG.CARD_DEPLOY_BLOCK),
      logsChunked(cardR, cardR.filters.CardMinted(), CONFIG.CARD_DEPLOY_BLOCK)]);
    const shoutTx = new Set(shouts.map((l) => l.transactionHash));
    gms.forEach((l) => { if (shoutTx.has(l.transactionHash)) return; const a = l.args; items.push({ b: l.blockNumber, i: l.index, tx: l.transactionHash, ic: "☀️", from: a.handle, html: `${hlink(a.handle)} said gm · <b>${a.streak}</b> day streak` }); });
    shouts.forEach((l) => { const a = l.args; items.push({ b: l.blockNumber, i: l.index, tx: l.transactionHash, ic: "📣", from: a.fromHandle, to: a.toHandle, html: `${hlink(a.fromHandle)} sent gm to ${hlink(a.toHandle)}` }); });
    mints.forEach((l) => { const a = l.args; items.push({ b: l.blockNumber, i: l.index, tx: l.transactionHash, ic: "🎴", from: a.handle, html: `${hlink(a.handle)} claimed a Kudos Card` }); });
  }
  items.sort((x, y) => y.b - x.b || y.i - x.i);
  cache.feed = items;
  renderFeed($("#feedHome"), items.slice(0, 12));
  renderFeed($("#feedBoard"), items.slice(0, 30));
}
function renderFeed(el, items) {
  el.innerHTML = items.length
    ? items.map((it) => `<li><div class="ic">${it.ic}</div><div>${it.html}<div class="when">block ${it.b.toLocaleString()} · <a target="_blank" rel="noopener" href="${CONFIG.EXPLORER}/tx/${it.tx}">tx</a></div></div></li>`).join("")
    : `<li class="muted">No activity yet. Be the first: <a class="grad" href="#/tip">send a tip</a>${CARD_LIVE ? ' or <a class="grad" href="#/gm">say gm</a>' : ""}.</li>`;
}

let boardTab = "recv";
$$("#boardTabs button").forEach((b) => (b.onclick = () => { boardTab = b.dataset.tab; $$("#boardTabs button").forEach((x) => x.classList.toggle("on", x === b)); renderBoard(); }));
function renderBoard() {
  const el = $("#board"); let rows = [];
  if (boardTab === "recv") {
    rows = Array.from(cache.recipients).sort((a, b) => Number(b.tipsReceived) - Number(a.tipsReceived)).slice(0, 25).map((r) =>
      `<li><div><div class="nm">${hlink(r.handle)}</div><div class="sub">${fmt(r.receivedNative)} BNB · $${Number(ethers.formatUnits(r.receivedTokenA + r.receivedTokenB, 18)).toFixed(2)}</div></div><div class="val">${r.tipsReceived}<div class="sub">kudos</div></div></li>`);
  } else if (boardTab === "tippers") {
    rows = cache.tippers.filter((t) => t.handle).sort((a, b) => Number(b.uniqueRecipients) - Number(a.uniqueRecipients) || Number(b.tipsSent) - Number(a.tipsSent)).slice(0, 25).map((t) =>
      `<li><div><div class="nm">${hlink(t.handle)}</div><div class="sub">${t.tipsSent} kudos sent</div></div><div class="val">${t.uniqueRecipients}<div class="sub">names</div></div></li>`);
  } else {
    if (!CARD_LIVE) { el.innerHTML = `<li class="muted">gm streaks open soon.</li>`; return; }
    rows = Array.from(cache.gms).sort((a, b) => Number(b.streak) - Number(a.streak) || Number(b.best) - Number(a.best) || Number(b.total) - Number(a.total)).slice(0, 25).map((g) =>
      `<li><div><div class="nm">${hlink(g.handle)}</div><div class="sub">best ${g.best} · ${g.total} gm${g.hasCard ? " · 🎴" : ""}</div></div><div class="val">${g.streak > 0 ? `${g.streak}🔥` : "0"}<div class="sub">streak</div></div></li>`);
  }
  el.innerHTML = rows.join("") || `<li class="muted">No entries yet. Be the first!</li>`;
}

async function loadGallery() {
  const el = $("#gallery");
  if (!CARD_LIVE) {
    el.innerHTML = ["Bronze", "Silver", "Gold", "Legend"].map((t, i) => `<div><img src="img/card-preview.svg" alt="" style="filter:hue-rotate(${i * 55}deg) saturate(${1 + i * 0.2})" /><div class="cap muted">${t} tier preview</div></div>`).join("");
    return;
  }
  const n = Number(await cardR.totalSupply());
  if (!n) { el.innerHTML = `<p class="muted">No cards yet. Claim the first one!</p>`; return; }
  const start = Math.max(0, n - 24);
  const handles = [...(await cardR.getCards(start, 24))].reverse();
  const uris = await Promise.all(handles.map((h) => cardR.tokenURI(BigInt(ethers.id(h))).catch(() => null)));
  el.innerHTML = handles.map((h, i) => { const d = uris[i] && svgFromURI(uris[i]); return d ? `<a href="#/${esc(h)}"><img loading="lazy" src="${d.image}" alt="${esc(h)}.ai card" /><div class="cap">${esc(h)}.ai</div></a>` : ""; }).join("");
}

// ---------------------------------------------------------------- profile #/handle
async function renderProfile(h) {
  const el = $("#profile");
  el.innerHTML = `<p class="muted">Loading ${esc(h)}.ai…</p>`;
  if (!HANDLE_RE.test(h)) { el.innerHTML = `<p class="err">Invalid name.</p>`; return; }
  try {
    const label = ethers.id(h);
    const p = await kudosR.profileOf(h);
    if (!p.registered) { el.innerHTML = `<div class="panel-h"><h2>${esc(h)}.ai</h2></div><p class="muted">This name is not a registered Agent ID.</p><a class="btn btn-glass" href="#/">Back home</a>`; return; }
    const z = (pr) => pr.catch(() => 0n);
    const [rb, ru, rc] = await Promise.all([z(kudosR.received(label, CONFIG.TOKENS.BNB.address)), z(kudosR.received(label, CONFIG.TOKENS.USDT.address)), z(kudosR.received(label, CONFIG.TOKENS.USDC.address))]);
    const sent = cache.tippers.find((t) => t.handle === h);
    let gmHtml = "", cardImg = "";
    if (CARD_LIVE) {
      const s = await cardR.statsOf(h).catch(() => null);
      gmHtml = `<div><b>${s ? s.streak : 0}🔥</b><span>gm streak</span></div>`;
      if (s?.hasCard) { const u = await cardR.tokenURI(BigInt(label)).catch(() => null); const d = u && svgFromURI(u); if (d) cardImg = `<div class="claim-art" style="margin:1rem 0"><img src="${d.image}" alt="${esc(h)}.ai card" /></div>`; }
    } else gmHtml = `<div><b>soon</b><span>gm streak</span></div>`;
    const activity = cache.feed.filter((it) => it.from === h || it.to === h).slice(0, 10);
    el.innerHTML = `
      <div class="prof-h"><div class="avatar">${esc(h[0].toUpperCase())}</div><div><h2>${esc(h)}<span class="grad">.ai</span></h2><div class="muted">${p.bio ? esc(p.bio) : "Agent ID on BNB Chain"}</div></div></div>
      <div class="prof-stats"><div><b>${p.tips}</b><span>kudos received</span></div><div><b>${sent ? sent.tipsSent : 0}</b><span>kudos sent</span></div>${gmHtml}</div>
      <div class="muted" style="font-size:.88rem">Received: ${fmt(rb)} BNB · ${fmt(ru)} USDT · ${fmt(rc)} USDC</div>
      ${cardImg}
      <div class="prof-actions" style="margin-top:1rem"><a class="btn btn-primary" href="#/tip" data-prefill="${esc(h)}">⚡ Tip ${esc(h)}.ai</a><a class="btn btn-glass" href="#/gm" data-gmprefill="${esc(h)}">📣 Send gm</a></div>
      <h3 style="margin:1.4rem 0 .4rem">Recent activity</h3><ul class="feed" id="profFeed"></ul>
      <p class="fine">Share: ${esc(location.origin + location.pathname)}#/${esc(h)}</p>`;
    renderFeed($("#profFeed"), activity);
    $("[data-prefill]", el).onclick = () => { setTimeout(() => { $("#to").value = h; checkName(h, $("#toInfo")); }, 0); };
    $("[data-gmprefill]", el).onclick = () => { setTimeout(() => { $("#gmTo").value = h; checkName(h, $("#gmToInfo")); }, 0); };
  } catch (e) { el.innerHTML = `<p class="muted">Could not load this profile right now.</p>`; }
}

// ---------------------------------------------------------------- router
const VIEWS = ["home", "tip", "gm", "board", "cards"];
function route() {
  let hash = location.hash || "#/";
  const legacy = hash.match(/^#to=([a-z0-9.]+)/i); // old share links
  if (legacy) { history.replaceState(null, "", "#/tip"); hash = "#/tip"; setTimeout(() => { $("#to").value = clean(legacy[1]); checkName(clean(legacy[1]), $("#toInfo")); }, 0); }
  const seg = clean(decodeURIComponent(hash.replace(/^#\/?/, "").split(/[/?]/)[0] || "home"));
  const view = VIEWS.includes(seg) ? seg : "profile";
  $$(".view").forEach((v) => v.classList.toggle("on", v.dataset.view === view));
  $$("[data-nav]").forEach((a) => a.classList.toggle("on", a.dataset.nav === view));
  if (view === "profile") renderProfile(seg);
  if (view === "board") renderBoard();
  window.scrollTo({ top: 0, behavior: "smooth" });
}
window.addEventListener("hashchange", route);

async function loadAll() {
  try { await loadStats(); } catch (e) { console.warn(e); }
  renderBoard();
  loadGallery().catch((e) => console.warn(e));
  try { await loadFeed(); } catch (e) { console.warn(e); }
  if (wallet.account) { refreshGm(); refreshCard(); }
}
route();
refreshGm(); refreshCard();
loadAll();
setInterval(loadAll, 60000);
// silent reconnect if the wallet already authorised this site (no prompt)
setTimeout(async () => { const p = pickProvider(); try { const a = p && (await p.request({ method: "eth_accounts" })); if (a && a.length) connect(); } catch {} }, 300);
