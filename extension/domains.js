// Spending Angel — shopping domain list.
//
// To add a domain: append it below. Use the bare hostname — no protocol,
// no www, no path. Examples:
//   "amazon.com"            matches amazon.com and any subdomain
//   "*.myshopify.com"       matches every Shopify-hosted store
//
// The match in content.js is suffix-based, so "amazon.com" also catches
// "smile.amazon.com" and "www.amazon.com".

var SPENDING_ANGEL_DOMAINS = [
  // Global giants
  "amazon.com", "amazon.es", "amazon.com.mx", "amazon.co.uk", "amazon.de", "amazon.ca",
  "ebay.com", "aliexpress.com", "alibaba.com", "temu.com", "shein.com", "wish.com",
  "etsy.com", "walmart.com", "target.com", "bestbuy.com", "costco.com", "ikea.com",
  "kohls.com", "macys.com", "wayfair.com",

  // Fashion
  "zara.com", "hm.com", "uniqlo.com", "asos.com", "zalando.com",
  "nike.com", "adidas.com", "lululemon.com", "gap.com", "urbanoutfitters.com",

  // Tech / electronics
  "apple.com", "bhphotovideo.com", "newegg.com", "microcenter.com", "samsung.com",

  // Marketplaces / ecosystems
  "shop.app", "*.myshopify.com",

  // DR / LATAM
  "mercadolibre.com", "mercadolibre.com.do", "mercadolibre.com.mx", "mercadolibre.com.ar",
  "jumbo.com.do", "plazalama.com.do", "cuestamoda.com",

  // Grocery / food delivery
  "instacart.com", "doordash.com", "ubereats.com", "grubhub.com",

  // Gaming / digital impulse
  "store.steampowered.com", "nintendo.com", "playstation.com", "xbox.com",
];

// Expose for the popup, which loads this same file via <script>.
if (typeof window !== "undefined") {
  window.SPENDING_ANGEL_DOMAINS = SPENDING_ANGEL_DOMAINS;
}
