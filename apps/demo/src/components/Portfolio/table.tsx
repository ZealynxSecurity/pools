import styled from 'styled-components'
import {
  FILECOIN_NUMBER_PROPTYPE,
  makeFriendlyBalance
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import PropTypes from 'prop-types'
import { useAccount } from 'wagmi'

import { usePoolTokenBalance } from '../../utils'

export const PortfolioRowColumnTitles = () => (
  <thead>
    <tr>
      <th>Pool Name</th>
      <th>Token Price</th>
      <th>Token Balance</th>
      <th>Value</th>
      <th>P/L</th>
    </tr>
  </thead>
)

const PLTD = styled.td`
  color: ${(props) => `var(${props.color})`};
`

const PL = ({ pl }: PLProps) => {
  let denom: string = ''
  if (pl > 0) denom = '+'

  return (
    <PLTD color={pl < 0 ? '--red-medium' : '--green-medium'}>
      {`${denom}${pl} FIL`}
    </PLTD>
  )
}

type PLProps = {
  pl: number
}

PL.propTypes = {
  pl: PropTypes.number.isRequired
}

export const PortfolioRow = (props: PortfolioRowProps) => {
  const { address } = useAccount()
  const { balance } = usePoolTokenBalance(props.poolID, address)

  return (
    <tr>
      <td>{props.name}</td>
      <td>{makeFriendlyBalance(props.exchangeRate.toFil(), 6, true)} FIL</td>
      <td>
        {makeFriendlyBalance(balance?.toFil(), 6, true)} p{props.poolID}GLIF
      </td>
      <td>
        {makeFriendlyBalance(
          balance?.times(props.exchangeRate).toFil(),
          6,
          true
        )}{' '}
        FIL
      </td>
      <PL pl={0} />
    </tr>
  )
}

type PortfolioRowProps = {
  poolAddress: string
  poolID: string
  exchangeRate: FilecoinNumber
  name: string
  walletAddress: string
}

PortfolioRow.propTypes = {
  poolAddress: PropTypes.string.isRequired,
  poolID: PropTypes.string.isRequired,
  exchangeRate: FILECOIN_NUMBER_PROPTYPE.isRequired,
  name: PropTypes.string.isRequired,
  walletAddress: PropTypes.string.isRequired
}
