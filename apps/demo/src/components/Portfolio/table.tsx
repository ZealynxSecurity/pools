import styled from 'styled-components'
import { makeFriendlyBalance } from '@glif/react-components'
import PropTypes from 'prop-types'
import { FilecoinNumber } from '@glif/filecoin-number'
import { useContractReads } from 'wagmi'

import contractDigest from '../../../generated/contractDigest.json'

const { SimpleInterestPool } = contractDigest

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
  const { data } = useContractReads({
    contracts: [
      {
        addressOrName: props.poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'id'
      },
      {
        addressOrName: props.poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'name'
      },
      {
        addressOrName: props.poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'previewDeposit',
        args: [1]
      },
      {
        addressOrName: props.poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'balanceOf',
        args: [props.walletAddress]
      }
    ]
  })

  const [id, name, pricePerShare, balance, val] =
    !!data && data.length > 0
      ? [
          data[0].toString(),
          data[1].toString(),
          data[2].toString(),
          makeFriendlyBalance(
            new FilecoinNumber(data[3].toString(), 'attofil'),
            4,
            true
          ),
          makeFriendlyBalance(
            new FilecoinNumber(data[3].toString(), 'attofil').times(5),
            4,
            true
          )
        ]
      : []

  const pl = 0

  return (
    <tr>
      <td>{name}</td>
      <td>{pricePerShare} FIL</td>
      <td>
        {balance} p{id}GLIF
      </td>
      <td>{val} FIL</td>
      <PL pl={pl} />
    </tr>
  )
}

type PortfolioRowProps = {
  poolAddress: string
  walletAddress: string
}

PortfolioRow.propTypes = {
  poolAddress: PropTypes.string.isRequired,
  walletAddress: PropTypes.string.isRequired
}
