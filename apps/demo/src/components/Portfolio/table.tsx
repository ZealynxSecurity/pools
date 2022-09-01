import styled from 'styled-components'
import { makeFriendlyBalance } from '@glif/react-components'
import PropTypes from 'prop-types'
import { BigNumber } from '@glif/filecoin-number'
import { random2DecimalFloat } from '../../utils'

export const PortfolioRowColumnTitles = () => (
  <thead>
    <tr>
      <th>Pool ID</th>
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
  // returns some random data for now
  const price = random2DecimalFloat(0, 10)
  const bal = random2DecimalFloat(95, 120)
  const val = makeFriendlyBalance(
    new BigNumber(Number(price) * Number(bal)),
    6,
    true
  )
  const pl =
    props.poolID === 1
      ? 0 - Number(random2DecimalFloat(10, 50))
      : Number(random2DecimalFloat(10, 50))

  return (
    <tr>
      <td>{props.poolID}</td>
      <td>{price} FIL</td>
      <td>
        {bal} p{props.poolID}GLIF
      </td>
      <td>{val} FIL</td>
      <PL pl={pl} />
    </tr>
  )
}

type PortfolioRowProps = {
  poolID: number
}

PortfolioRow.propTypes = {
  poolID: PropTypes.number.isRequired
}
