const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'aw-obdsystem';
const post = (name, data = {}) => fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
}).catch(() => {});

const $ = (s, r = document) => r.querySelector(s);

const state = {
    page: 'scan',
    L: {},
    codes: {},
    access: {},
    plate: '',
    model: '',
    km: 0,
    history: [],
    scan: null,
    forensic: null,
    scanning: false,
    pct: 0,
    log: [],
    glog: [],
    busy: false,
    live: null,
    ghostShown: false,
    clicks: 0,
    token: 0,
    pageTok: 0,
    ovl: false,
    fLoading: false
};

const pages = ['scan', 'dtc', 'health', 'history', 'report', 'live'];
const metrics = ['engine', 'body', 'fuelsys', 'fuel', 'oil', 'battery', 'brakes', 'tyres'];
const actions = ['mileage', 'clearlog', 'wipeflag', 'plate', 'tune', 'unlock', 'immobilize'];

const t = k => state.L[k] || k;
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pad = n => String(n).padStart(2, '0');
const fmtDate = ts => {
    const d = new Date(ts * 1000);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const fmtKm = n => `${Number(n).toLocaleString('en-US').replace(/,/g, ' ')} km`;
const avg = h => Math.round(Object.values(h).reduce((a, b) => a + b, 0) / Object.values(h).length);

const gate = () => `<div class="empty">${t('scan_first')}</div><button class="btn" data-go="scan">${t('nav_scan')}</button>`;

const views = {
    scan() {
        const s = state.scan;
        const pct = state.scanning ? state.pct : (s ? 100 : 0);
        return `<h2>${t('scan_title')}</h2>
        <p class="muted">${t('scan_hint')}</p>
        <div class="odo"><span>${t('odometer')}</span><b>${fmtKm(state.km)}</b></div>
        <div class="term" id="term">${state.log.map(l => `<div>${esc(l)}</div>`).join('')}</div>
        <div class="bar"><i style="width:${pct}%"></i></div>
        <button class="btn" id="runscan" ${state.scanning ? 'disabled' : ''}>${state.scanning ? t('scan_running') : t('scan_run')}</button>
        ${s ? `<div class="stats">
            <div><b>${s.dtc.length}</b><span>${t('stat_dtc')}</span></div>
            <div><b>${avg(s.health)}%</b><span>${t('stat_health')}</span></div>
            <div><b>${esc(s.id)}</b><span>${t('report_id')}</span></div>
        </div>` : ''}`;
    },

    dtc() {
        const s = state.scan;
        if (!s) return gate();
        return `<h2>${t('dtc_title')}</h2><div style="margin-top:20px">${s.dtc.length
            ? s.dtc.map(c => `<div class="dtc ${c.sev}"><b>${c.code}</b><p>${esc(state.codes[c.code] || c.code)}</p><em>${t('sev_' + c.sev)}</em></div>`).join('')
            : `<div class="empty">${t('dtc_none')}</div>`}</div>`;
    },

    health() {
        const s = state.scan;
        if (!s) return gate();
        return `<h2>${t('health_title')}</h2><div class="grid2">${metrics.map(k => {
            const v = s.health[k];
            return `<div class="metric"><div class="mh"><span>${t('h_' + k)}</span><b>${v}%</b></div><div class="bar${v < 30 ? ' crit' : ''}"><i style="width:${v}%"></i></div></div>`;
        }).join('')}</div>`;
    },

    history() {
        const h = [...state.history].reverse();
        return `<h2>${t('history_title')}</h2>${h.length
            ? `<table><thead><tr><th>${t('th_date')}</th><th>${t('th_mileage')}</th><th>${t('th_by')}</th><th>${t('th_dtc')}</th><th>${t('th_health')}</th></tr></thead><tbody>${h.map(e => `<tr><td>${fmtDate(e.t)}</td><td>${fmtKm(e.km)}</td><td>${esc(e.by)}</td><td>${e.dtc}</td><td>${e.hp}%</td></tr>`).join('')}</tbody></table>`
            : `<div class="empty">${t('history_empty')}</div>`}`;
    },

    report() {
        const s = state.scan;
        if (!s) return gate();
        return `<div class="paper">
            <div class="ph"><div><b>ARUHAWORKS</b><span>${t('report_title')}</span></div><div class="rid">${esc(s.id)}</div></div>
            <div class="row"><span>${t('report_vehicle')}</span><b>${esc(s.model || '-')}</b></div>
            <div class="row"><span>${t('report_plate')}</span><b>${esc(s.plate)}</b></div>
            <div class="row"><span>${t('report_date')}</span><b>${fmtDate(s.time)}</b></div>
            <div class="row"><span>${t('report_tech')}</span><b>${esc(s.tech)}</b></div>
            <div class="row"><span>${t('report_mileage')}</span><b>${fmtKm(s.km)}</b></div>
            <div class="row"><span>${t('stat_health')}</span><b>${avg(s.health)}%</b></div>
            <h4>${t('report_summary')}</h4>
            ${s.dtc.length ? s.dtc.map(c => `<div class="fl">${c.code} - ${esc(state.codes[c.code] || c.code)}</div>`).join('') : `<div class="fl">${t('report_ok')}</div>`}
            <div class="barcode"></div>
        </div>`;
    },

    live() {
        const g = [['speed', 'l_speed', 'km/h'], ['rpm', 'l_rpm', 'rpm'], ['gear', 'l_gear', ''], ['temp', 'l_temp', '&deg;C'], ['volt', 'l_volt', 'V'], ['fuel', 'l_fuel', '%'], ['engine', 'l_engine', '%']];
        return `<h2>${t('live_title')}</h2><div class="gauges">${g.map(([k, l, u]) =>
            `<div class="gauge"><span>${t(l)}</span><b id="lv-${k}">-</b><em>${u}</em><div class="bar"><i id="lb-${k}"></i></div></div>`).join('')}</div>`;
    },

    forensic() {
        const f = state.forensic;
        let out = `<h2>${t('forensic_title')}</h2><p class="muted">${t('f_hint')}</p><button class="btn" id="runf" ${state.fLoading ? 'disabled' : ''}>${t('f_run')}</button>`;
        if (state.fLoading) out += `<div class="loadline">${t('loading')}...</div>`;
        if (f) {
            out += `<div class="stats">
                <div><b>${f.tamper}</b><span>${t('f_tamper')}</span></div>
                <div><b>${f.tamper > 0 ? t('f_anomaly') : t('f_clean')}</b><span>${t('f_status')}</span></div>
                <div><b>${f.stolen ? t('yes') : t('no')}</b><span>${t('f_stolen')}</span></div>
            </div>
            <div class="odo" style="margin-top:14px"><span>${t('f_last')}</span><b style="font-size:16px">${f.last ? `${t('a_' + f.last)} / ${fmtDate(f.lastAt)}` : t('f_none')}</b></div>
            <button class="btn" id="flag" ${state.fLoading ? 'disabled' : ''}>${f.stolen ? t('f_flag_clear') : t('f_flag_set')}</button>`;
        }
        return out;
    },

    ghost() {
        return `<h2 class="glitch" data-text="${t('ghost_title')}">${t('ghost_title')}</h2>
        <p class="muted">${t('ghost_warn')}</p>
        <div class="acts">${actions.map(a => `<div class="act">
            <div><b>${t('a_' + a)}</b><p>${t('d_' + a)}</p></div>
            ${a === 'mileage' ? `<input id="in-km" type="number" min="0" placeholder="${t('target_km')}">` : ''}
            ${a === 'plate' ? `<input id="in-plate" maxlength="8" placeholder="${t('new_plate')}">` : ''}
            <button class="btn sm" data-act="${a}" ${state.busy ? 'disabled' : ''}>${t('execute')}</button>
        </div>`).join('')}</div>
        <div class="term" id="gterm">${state.glog.map(l => `<div>${esc(l)}</div>`).join('')}</div>`;
    }
};

function nav() {
    const items = [...pages];
    if (state.access.police) items.push('forensic');
    if (state.ghostShown) items.push('ghost');
    $('#nav').innerHTML = items.map((p, i) =>
        `<button class="nav-item${state.page === p ? ' on' : ''}${p === 'ghost' ? ' ghost-nav' : ''}" data-p="${p}"><span>${pad(i + 1)}</span>${t('nav_' + p)}</button>`
    ).join('') + '<div class="nav-foot">AW // v2.0</div>';
}

function render() {
    $('#view').innerHTML = views[state.page]();
    const term = $('#term') || $('#gterm');
    if (term) term.scrollTop = term.scrollHeight;
    if (state.page === 'live' && state.live) paintLive(state.live);
}

function go(p, instant) {
    state.page = p;
    document.body.classList.toggle('ghost', p === 'ghost');
    nav();
    if (instant) return render();
    const tok = ++state.pageTok;
    $('#view').innerHTML = '<div class="skel"><i></i><i></i><i></i><i></i></div>';
    setTimeout(() => { if (tok === state.pageTok) render(); }, 260);
}

function overlay(title, lines, ms, done) {
    const tok = state.token;
    const o = $('#overlay');
    const log = $('#olog');
    const bar = $('#obar');
    state.ovl = true;
    $('#otitle').textContent = title;
    log.innerHTML = '';
    bar.style.transition = 'none';
    bar.style.width = '0';
    o.classList.remove('hidden');
    requestAnimationFrame(() => requestAnimationFrame(() => {
        bar.style.transition = `width ${ms}ms linear`;
        bar.style.width = '100%';
    }));
    lines.forEach((l, i) => setTimeout(() => {
        if (tok === state.token) log.insertAdjacentHTML('beforeend', `<div>> ${esc(l)}</div>`);
    }, (ms / lines.length) * i));
    setTimeout(() => {
        if (tok !== state.token) return;
        state.ovl = false;
        o.classList.add('hidden');
        if (done) done();
    }, ms + 150);
}

function paintLive(d) {
    const set = (k, text, pct) => {
        const v = $(`#lv-${k}`);
        const b = $(`#lb-${k}`);
        if (v) v.textContent = text;
        if (b) b.style.width = `${Math.max(0, Math.min(100, pct))}%`;
    };
    set('speed', d.speed, d.speed / 2.5);
    set('rpm', d.rpm, d.rpm / 80);
    set('gear', d.gear === 0 ? 'N' : d.gear, d.gear * 16.6);
    set('temp', d.temp, (d.temp - 20) / 1.1);
    set('volt', Number(d.volt).toFixed(1), (d.volt - 10) * 20);
    set('fuel', d.fuel, d.fuel);
    set('engine', d.engine, d.engine);
}

function runScan() {
    if (state.scanning) return;
    state.scanning = true;
    state.log = [];
    state.pct = 0;
    render();
    const steps = ['scan_s1', 'scan_s2', 'scan_s3', 'scan_s4', 'scan_s5', 'scan_s6'];
    let i = 0;
    const tick = setInterval(() => {
        if (i < steps.length) {
            state.log.push(`> ${t(steps[i])}`);
            i++;
            state.pct = Math.round(i / steps.length * 90);
            if (state.page === 'scan') render();
        } else {
            clearInterval(tick);
            post('scan');
        }
    }, 420);
}

function police(op) {
    state.fLoading = true;
    render();
    post('police', { op });
    setTimeout(() => {
        if (state.fLoading) {
            state.fLoading = false;
            if (state.page === 'forensic') render();
        }
    }, 5000);
}

function execute(a) {
    const extra = {};
    if (a === 'mileage') extra.km = Number($('#in-km').value);
    if (a === 'plate') extra.plate = $('#in-plate').value.toUpperCase();
    post('begin', { action: a, extra });
}

function reveal() {
    const b = $('#brand');
    b.classList.add('glitch-b');
    setTimeout(() => b.classList.remove('glitch-b'), 500);
    if (!state.access.ghost || state.ovl) return;
    if (state.ghostShown) return go('ghost');
    document.body.classList.add('ghost');
    overlay(t('unlock_title'), [t('unlock_1'), t('unlock_2'), t('unlock_3'), t('unlock_4')], 1900, () => {
        state.ghostShown = true;
        go('ghost', true);
    });
}

$('#brand').addEventListener('click', () => {
    state.clicks++;
    if (state.clicks === 1) setTimeout(() => { state.clicks = 0; }, 2500);
    if (state.clicks >= 5) {
        state.clicks = 0;
        reveal();
    }
});

$('#nav').addEventListener('click', e => {
    const b = e.target.closest('.nav-item');
    if (b) go(b.dataset.p);
});

$('#view').addEventListener('click', e => {
    const go_ = e.target.closest('[data-go]');
    if (go_) return go(go_.dataset.go);
    const act = e.target.closest('[data-act]');
    if (act) return execute(act.dataset.act);
    if (e.target.closest('#runscan')) return runScan();
    if (e.target.closest('#runf')) return police('forensic');
    if (e.target.closest('#flag')) return police('flag');
});

$('#close').addEventListener('click', () => post('close'));
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') post('close');
});

setInterval(() => {
    const d = new Date();
    $('#clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}, 1000);

window.addEventListener('message', e => {
    const m = e.data;
    switch (m.action) {
        case 'open':
            Object.assign(state, {
                L: m.locale,
                codes: m.codes,
                access: { ghost: m.data.ghost, police: m.data.police },
                plate: m.data.plate,
                model: m.model,
                km: m.data.km,
                history: m.data.history || [],
                scan: null,
                forensic: null,
                scanning: false,
                log: [],
                glog: [],
                busy: false,
                live: null,
                ghostShown: false,
                clicks: 0,
                fLoading: false,
                ovl: false
            });
            state.token++;
            document.querySelectorAll('[data-t]').forEach(el => { el.textContent = t(el.dataset.t); });
            $('#model').textContent = state.model;
            $('#plate').textContent = state.plate;
            $('#progress').classList.add('hidden');
            $('#root').classList.remove('hidden');
            go('scan', true);
            overlay(t('boot_title'), [t('boot_1'), t('boot_2'), t('boot_3'), t('boot_4')], 1600, () => {
                if (m.data.autoGhost && state.access.ghost) reveal();
            });
            break;

        case 'close':
            state.token++;
            state.ovl = false;
            $('#overlay').classList.add('hidden');
            $('#root').classList.add('hidden');
            document.body.classList.remove('ghost');
            break;

        case 'scan':
            state.scan = m.data;
            state.km = m.data.km;
            state.history = m.data.history;
            state.scanning = false;
            state.pct = 100;
            state.log.push(`> ${t('scan_done')}`);
            render();
            break;

        case 'live':
            state.live = m.data;
            if (state.page === 'live') paintLive(m.data);
            break;

        case 'forensic':
            state.forensic = m.data;
            state.fLoading = false;
            if (state.page === 'forensic') render();
            break;

        case 'progress': {
            state.busy = true;
            $('#plabel').textContent = t(`a_${m.key}`).toUpperCase();
            const bar = $('#pbar');
            bar.style.transition = 'none';
            bar.style.width = '0';
            $('#progress').classList.remove('hidden');
            requestAnimationFrame(() => requestAnimationFrame(() => {
                bar.style.transition = `width ${m.duration}ms linear`;
                bar.style.width = '100%';
            }));
            break;
        }

        case 'progressStop':
            state.busy = false;
            $('#progress').classList.add('hidden');
            state.glog.push(`> ${t('glog_cancel')}`);
            if (state.page === 'ghost') render();
            break;

        case 'applied':
            state.busy = false;
            state.km = m.km;
            state.history = m.history;
            $('#progress').classList.add('hidden');
            state.glog.push(`> ${t(`a_${m.key}`)} ... ${t('glog_ok')}`);
            render();
            break;
    }
});
