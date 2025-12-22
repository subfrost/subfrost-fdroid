import QRCode from 'qrcode';

const REPO_URL = 'fdroidrepos://f-droid.subfrost.io/fdroid/repo?fingerprint=6B4042D2CA47800272055F3B42299BB091711C0BCCFA9BEA02F05657046E4F21';

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
