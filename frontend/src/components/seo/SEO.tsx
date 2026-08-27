import { Helmet } from 'react-helmet-async';
import { LOGO_SRC } from '@/components/brand/Logo';

interface SEOProps {
    title?: string;
    description?: string;
    canonical?: string;
    image?: string;
    type?: 'website' | 'article' | 'product';
    keywords?: string;
    creator?: string;
}

// Padrões da marca Safegold. As URLs são relativas de propósito — o host
// público vem do deploy (ENV `alias` no legado); cravar um domínio aqui
// produziria preview quebrado no ambiente errado. Mesmo critério do index.html.
const DEFAULT_TITLE = 'Safegold — gestão de risco, recebíveis e operações estruturadas';
const DEFAULT_DESCRIPTION =
    'Borderô e recebíveis, operações estruturadas, renegociações, limites por portador e indicadores de carteira em um lugar só.';
const DEFAULT_IMAGE = '/og-safegold.png';
const DEFAULT_KEYWORDS =
    'gestão de risco de crédito, recebíveis, borderô, operação estruturada, renegociação, limite por portador, indicadores de carteira, Safegold';

export function SEO({
    title = DEFAULT_TITLE,
    description = DEFAULT_DESCRIPTION,
    canonical = '/',
    image = DEFAULT_IMAGE,
    type = "website",
    keywords = DEFAULT_KEYWORDS,
    creator = "@safegold"
}: SEOProps) {

    const siteTitle = title.includes('Safegold') ? title : `${title} | Safegold`;

    const jsonLd = {
        "@context": "https://schema.org",
        "@type": "Organization",
        "name": "Safegold",
        // Caminho vindo do catálogo da marca, nunca digitado aqui: o JSON-LD
        // precisa da string e não pode renderizar `<Logo>`, mas a lista de
        // arquivos continua morando num lugar só.
        "logo": LOGO_SRC.brand.full.light,
        "description": description
    };

    return (
        <Helmet>
            {/* Basic */}
            <title>{siteTitle}</title>
            <meta name="description" content={description} />
            <meta name="keywords" content={keywords} />
            <link rel="canonical" href={canonical} />

            {/* Open Graph / Facebook / WhatsApp */}
            <meta property="og:type" content={type} />
            <meta property="og:url" content={canonical} />
            <meta property="og:title" content={siteTitle} />
            <meta property="og:description" content={description} />
            <meta property="og:image" content={image} />
            <meta property="og:locale" content="pt_BR" />
            <meta property="og:site_name" content="Safegold" />

            {/* Twitter */}
            <meta name="twitter:card" content="summary_large_image" />
            <meta name="twitter:creator" content={creator} />
            <meta name="twitter:title" content={siteTitle} />
            <meta name="twitter:description" content={description} />
            <meta name="twitter:image" content={image} />

            {/* JSON-LD */}
            <script type="application/ld+json">
                {JSON.stringify(jsonLd)}
            </script>
        </Helmet>
    );
}
