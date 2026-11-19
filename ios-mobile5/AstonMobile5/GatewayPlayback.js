(function () {
    'use strict';
    var request = __ASTON_REQUEST__;
    window.__astonMobileRequest = request.requestId;
    var video = document.getElementById('video');
    if (!video) throw Error('Video surface missing');
    function notify(value) { window.webkit.messageHandlers.videoState.postMessage(value); }

    // Use CSSOM properties, respecting the deployed Gateway's style-src policy.
    document.body.style.margin = '0';
    document.body.style.background = '#000';
    document.body.style.overflow = 'hidden';
    Array.from(document.body.children).forEach(function (node) {
        if (node !== video) node.style.visibility = 'hidden';
    });
    document.body.appendChild(video);
    video.setAttribute('playsinline', '');
    Object.assign(video.style, {visibility:'visible', position:'fixed', inset:'0', width:'100%', height:'100%', objectFit:'contain', background:'#000'});
    if (!video.dataset.astonEvents) {
        video.dataset.astonEvents = '1';
        ['playing', 'pause', 'waiting', 'error'].forEach(function (event) {
            video.addEventListener(event, function () { notify({state:event}); });
        });
        video.addEventListener('timeupdate', function () {
            var ranges = video.seekable;
            notify({seekable:!!(ranges.length && ranges.end(ranges.length - 1) - ranges.start(0) > 2)});
        });
        var status = document.getElementById('status');
        if (status) new MutationObserver(function () {
            if (/грешка|неподдържан|липсва|изтече/i.test(status.textContent)) notify({state:'error'});
        }).observe(status, {childList:true, characterData:true, subtree:true});
    }
    // Gateway functions are private to its IIFE. Drive the real DOM event handler.
    // didFinish occurs before the asynchronous channel catalogue necessarily arrives.
    var attempts = 0;
    function selectChannel() {
        if (window.__astonMobileRequest !== request.requestId) return;
        var buttons = document.querySelectorAll('#channelRail [data-id]');
        for (var i = 0; i < buttons.length; i++) {
            if (buttons[i].getAttribute('data-id') === request.channel) {
                buttons[i].click();
                return;
            }
        }
        if (++attempts < 120) { setTimeout(selectChannel, 250); return; }
        var auth = document.getElementById('authView');
        notify({state:auth && !auth.classList.contains('hidden') ? 'pairing' : 'missing-channel'});
    }
    selectChannel();
    return true;
})();
