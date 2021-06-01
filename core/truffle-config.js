module.exports = {
    networks: {
        development: {
            host: 'localhost', // Localhost (default: none)
            port: 8545, // Standard Ethereum port (default: none)
            network_id: '*', // Any network (default: none)
            gas: 10000000,
        },
    },
    // Configure your compilers
    compilers: {
        solc: {
            version: '0.8.4',
            settings: { // See the solidity docs for advice about optimization and evmVersion
                optimizer: {
                    enabled: true,
                    runs: 100,
                },
                evmVersion: 'berlin',
            },
        },
    },
    plugins: ['solidity-coverage'],
};
