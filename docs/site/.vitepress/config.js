export default {
    title: 'NSPds Tutorial',
    description: 'Building an AT Protocol PDS in Objective-C',
    themeConfig: {
        nav: [
            { text: 'Home', link: '/' },
            { text: 'Tutorial', link: '/tutorial/01-introduction-to-objective-c' },
        ],
        sidebar: [
            {
                text: 'Part I: Fundamentals',
                items: [
                    { text: '1. Intro to Objective-C', link: '/tutorial/01-introduction-to-objective-c' },
                    { text: '2. Foundation Framework', link: '/tutorial/02-foundation-framework' },
                    { text: '3. Build Systems', link: '/tutorial/03-build-systems' },
                    { text: '4. Content Identifiers', link: '/tutorial/04-content-identifiers' },
                ]
            },
            {
                text: 'Part II: Data Structures',
                items: [
                    { text: '5. CBOR Serialization', link: '/tutorial/05-cbor-serialization' },
                    { text: '6. Merkle Search Trees', link: '/tutorial/06-merkle-search-trees' },
                    { text: '7. CAR Files & Commits', link: '/tutorial/07-car-files-commits' },
                ]
            },
            {
                text: 'Part III: Cryptography',
                items: [
                    { text: '8. secp256k1 Crypto', link: '/tutorial/08-secp256k1-cryptography' },
                    { text: '9. Decentralized IDs', link: '/tutorial/09-decentralized-identifiers' },
                    { text: '10. PLC Operations', link: '/tutorial/10-plc-operations' },
                ]
            },
            {
                text: 'Part IV: Networking',
                items: [
                    { text: '11. HTTP Server', link: '/tutorial/11-http-server' },
                    { text: '12. XRPC Endpoints', link: '/tutorial/12-xrpc-endpoints' },
                ]
            },
            {
                text: 'Part V: Storage & Integration',
                items: [
                    { text: '13. SQLite Database', link: '/tutorial/13-sqlite-database' },
                    { text: '14. OAuth & JWT', link: '/tutorial/14-oauth-jwt' },
                    { text: '15. Complete PDS', link: '/tutorial/15-complete-pds' },
                ]
            }
        ],
        socialLinks: [
            { icon: 'github', link: 'https://github.com/myuser/objpds' }
        ]
    }
}
