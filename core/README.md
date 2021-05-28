<h1 align=center><code>kassandra</code></h1>

## Documentation

The full documentation can be found at <https://docs.kassandra.finance>

## Development

Most users will want to consume the ABI definitions for Factory and Pool.

This project follows the standard Truffle project structure. 

```
yarn compile   # build artifacts to `build/contracts`
yarn testrpc # run ganache
yarn test    # run the tests
```

Tests can be run verbosely to view approximation diffs:

```
$ yarn test:verbose
```

```
  Contract: Pool
    With fees
pAi
expected: 10.891089108910892)
actual  : 10.891089106783580001)
relDif  : 1.9532588879656032e-10)
Pool Balance
expected: 98010000000000030000)
actual  : 98010000001320543977)
relDif  : 1.3473294888276702e-11)
Dirt Balance
expected: 3921200210105053000)
actual  : 3921200210099248361)
relDif  : 1.480428360949332e-12)
Rock Balance
expected: 11763600630315160000)
actual  : 11763600630334527239)
relDif  : 1.6464292361378058e-12)
      ✓ exitswap_ExternAmountOut (537ms)
```

## License

Kassandra Finance, an open and decentralized investment fund. Copyright (C) 2021  Kassandra Finance <https://kassadra.finance>

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

## Credits

This code was made on the foundations laid by [Balancer](https://balancer.finance/) on their [core contracts](https://github.com/balancer-labs/balancer-core) at commit [f4ed5d6](https://github.com/balancer-labs/balancer-core/commit/f4ed5d65362a8d6cec21662fb6eae233b0babc1f) which are also licensed under the GPLv3 license. Thanks to their efforts we could expand DeFi even further.
