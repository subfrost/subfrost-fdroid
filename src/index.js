import QRCode from 'qrcode';

const REPO_URL = 'fdroidrepos://f-droid.subfrost.io/fdroid/repo?fingerprint=0CFA709EE2D376CB72791EF8DC453A97DCCF9EB8E2995B9260939D0722772EDE';

document.addEventListener('DOMContentLoaded', () => {
    const qrcodeContainer = document.getElementById('qrcode');
    const canvas = document.createElement('canvas');
    qrcodeContainer.appendChild(canvas);

    QRCode.toCanvas(canvas, REPO_URL, {
        width: 180,
        margin: 0,
        color: {
            dark: '#000000',
            light: '#ffffff'
        }
    });
});
