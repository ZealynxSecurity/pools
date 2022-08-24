import { space, StandardBox } from '@glif/react-components'
import styled from 'styled-components'
import { DataPoint } from '../generic'

const OnChainStatsWrapper = styled(StandardBox)`
  display: flex;
  flex-wrap: wrap;

  > * {
    align-items: flex-start;

    &:first-child {
      width: 100%;

      p {
        margin-top: ${space()};
        padding-top: ${space()};
      }
    }

    &:last-child {
      h2 {
        margin-bottom: ${space()};
        padding-bottom: ${space()};
      }
    }
  }
`

function OnChainStats() {
  return (
    <OnChainStatsWrapper>
      <DataPoint>
        <p>Pool #</p>
        <h2>1</h2>
      </DataPoint>
      <DataPoint>
        <p>Name</p>
        <h2>Conservative miner index</h2>
      </DataPoint>
      <DataPoint>
        <p>Exit Liquidity</p>
        <h2>200,000 FIL</h2>
      </DataPoint>
      <DataPoint>
        <p>Current APY</p>
        <h2>22.36%</h2>
      </DataPoint>
      <DataPoint>
        <p>Total Assets</p>
        <h2>1,200,000 FIL</h2>
      </DataPoint>
      <DataPoint>
        <p>Working Assets</p>
        <h2>384,000 FIL</h2>
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

export function Education() {
  return (
    <EducationWrapper>
      <OnChainStats />
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
