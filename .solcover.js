module.exports = {
  port: 8555,
  testrpcOptions: "-p 8555 -d",
  skipFiles: [
    'Migrations.sol',
    'interfaces',
    'mocks',
    'test',
  ],
};