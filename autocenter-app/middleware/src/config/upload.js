const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Usa /tmp/coliseu_uploads para contornar problemas de permissão (EACCES) em containers Docker Restritos
const uploadDir = process.env.UPLOAD_DIR || path.join(require('os').tmpdir(), 'coliseu_uploads');

if (!fs.existsSync(uploadDir)) {
    try {
        fs.mkdirSync(uploadDir, { recursive: true });
    } catch (e) {
        console.error('[Upload Config] Falha ao criar diretório de uploads. Verifique as permissões:', e.message);
    }
}

const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadDir);
    },
    filename: function (req, file, cb) {
        // Gera um nome único para a foto
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, 'quote-' + uniqueSuffix + ext);
    }
});

const fileFilter = (req, file, cb) => {
    // Aceita apenas imagens
    if (file.mimetype.startsWith('image/')) {
        cb(null, true);
    } else {
        cb(new Error('Formato não suportado. Envie apenas imagens.'), false);
    }
};

const upload = multer({ 
    storage: storage,
    fileFilter: fileFilter,
    limits: {
        fileSize: 10 * 1024 * 1024 // Limite de 10MB por arquivo (já deve vir comprimido do mobile)
    }
});

module.exports = upload;
