// openar: load page blocks in parallel after the frame is shown (LuCI "Loading view..." pattern).
// Elements with data-block="<name>" (status blocks) or data-cmd="<id>" ("auto" commands) are
// replaced by the HTML of /cgi-bin/view/block.cgi?b=|?c=. Basic auth is reused by the browser.
document.querySelectorAll('[data-block],[data-cmd]').forEach(function (el) {
	var b = el.getAttribute('data-block'), c = el.getAttribute('data-cmd'), q;
	if (b !== null) q = 'b=' + encodeURIComponent(b);
	else q = 'c=' + encodeURIComponent(c);
	fetch('/cgi-bin/view/block.cgi?' + q, { credentials: 'same-origin', cache: 'no-store' })
		.then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
		.then(function (html) {
			var t = document.createElement('div');
			t.innerHTML = html;
			var n = t.firstElementChild || t;
			n.classList.add('flash');
			el.replaceWith(n);
		})
		.catch(function (e) {
			var p = el.querySelector('.spinning');
			if (p) { p.classList.remove('spinning'); p.textContent = 'Load failed: ' + e.message; }
		});
});
