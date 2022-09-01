import PropTypes from 'prop-types'

import { TableHeader } from '../generic'
import { PortfolioRow, PortfolioRowColumnTitles } from './table'

export function Holdings({ poolAddrs, walletAddress }: HoldingsProps) {
  return poolAddrs && poolAddrs.length > 0 ? (
    <>
      <br />
      <TableHeader>Your Holdings</TableHeader>
      <table>
        <PortfolioRowColumnTitles />
        <tbody>
          {poolAddrs.map((poolAddr, i) => (
            <PortfolioRow
              key={i}
              poolAddress={poolAddr}
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
  poolAddrs: string[]
  walletAddress: string
}

Holdings.propTypes = {
  poolAddrs: PropTypes.arrayOf(PropTypes.string).isRequired,
  walletAddress: PropTypes.string.isRequired
}
