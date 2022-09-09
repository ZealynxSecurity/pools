import { FilecoinNumber } from '@glif/filecoin-number'
import {
  Colors,
  CopyText,
  space,
  StandardBox,
  truncateAddress
} from '@glif/react-components'
import styled from 'styled-components'
import { DataPoint } from '../generic'

const OnChainStatsWrapper = styled(StandardBox)`
  display: flex;
  flex-wrap: wrap;

  > * {
    &:last-child {
      h2 {
        margin-bottom: ${space()};
        padding-bottom: ${space()};
      }
    }
  }
`

function OnChainStats(props: EducationProps) {
  return (
    <OnChainStatsWrapper>
      <DataPoint>
        <p>Pool #</p>
        <h2>{props.poolID}</h2>
      </DataPoint>
      <DataPoint>
        <p>Pool Address</p>
        <span>
          <h2>{truncateAddress(props.poolAddress)} </h2>
          <CopyText text={props.poolAddress} color={Colors.PURPLE_MEDIUM} />
        </span>
      </DataPoint>
      <DataPoint>
        <p>Name</p>
        <h2>{props.name}</h2>
      </DataPoint>
      <DataPoint>
        <p>Exit Liquidity</p>
        <h2>{props.exitLiquidity}</h2>
      </DataPoint>
      <DataPoint>
        <p>Current APY</p>
        <h2>{props.interestRate.toFil()}%</h2>
      </DataPoint>
      <DataPoint>
        <p>Total Assets</p>
        <h2>{props.totalAssets.toFil()} FIL</h2>
      </DataPoint>
      <DataPoint>
        <p>Working Assets</p>
        <h2>{props.workingAssets}</h2>
      </DataPoint>
    </OnChainStatsWrapper>
  )
}

const EducationWrapper = styled.div`
  width: 75%;
  margin-left: auto;
  margin-right: auto;

  > * {
    margin-bottom: ${space()};
  }
`

export function Education(props: EducationProps) {
  return (
    <EducationWrapper>
      <OnChainStats {...props} />
      <StandardBox>
        <h2>About</h2>
        <p>
          Lorem Ipsum is simply dummy text of the printing and typesetting
          industry. Lorem Ipsum has been the industry standard dummy text ever
          since the 1500s, when an unknown printer took a galley of type and
          scrambled it to make a type specimen book.{' '}
        </p>
      </StandardBox>
      <StandardBox>
        <h2>Strategy</h2>
        <p>
          Lorem Ipsum is simply dummy text of the printing and typesetting
          industry. Lorem Ipsum has been the industry standard dummy text ever
          since the 1500s, when an unknown printer took a galley of type and
          scrambled it to make a type specimen book.{' '}
        </p>
      </StandardBox>
    </EducationWrapper>
  )
}

type EducationProps = {
  poolID: string
  poolAddress: string
  name: string
  exitLiquidity: FilecoinNumber
  interestRate: FilecoinNumber
  totalAssets: FilecoinNumber
  workingAssets: FilecoinNumber
}
