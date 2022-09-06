import PropTypes from 'prop-types'
import { POOLS_PROP_TYPE } from '../../customPropTypes'
import { Pool } from '../../utils'

import { TableHeader } from '../generic'
import { PortfolioRow, PortfolioRowColumnTitles } from './table'

export function Holdings({ pools, walletAddress }: HoldingsProps) {
  return pools.length > 0 ? (
    <>
      <br />
      <TableHeader>Your Holdings</TableHeader>
      <table>
        <PortfolioRowColumnTitles />
        <tbody>
          {pools.map((pool, i) => (
            <PortfolioRow
              key={i}
              poolAddress={pool.address}
              poolID={pool.id}
              name={pool.name}
              exchangeRate={pool.exchangeRate}
              walletAddress={walletAddress}
            />
          ))}
        </tbody>
      </table>
    </>
  ) : (
    <div>Loading...</div>
  )
}

type HoldingsProps = {
  pools: Pool[]
  walletAddress: string
}

Holdings.propTypes = {
  pools: POOLS_PROP_TYPE.isRequired,
  walletAddress: PropTypes.string.isRequired
}
