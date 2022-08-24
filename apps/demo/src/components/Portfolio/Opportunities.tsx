import PropTypes from 'prop-types'
import { ButtonV2, ShadowBox, space } from '@glif/react-components'
import styled from 'styled-components'
import { DataPoint } from '../generic'

const OppContainer = styled.div`
  width: 100%;
  justify-self: center;
  align-self: center;
  display: flex;
  flex-direction: row;

  > button {
    border: none;
    padding: 0;
    margin: 0;
  }
`

const DataContainer = styled.div`
  width: 100%;
  display: flex;
  flex-direction: row;
  justify-content: space-around;
  flex-grow: 1;

  border-bottom: 1px solid var(--gray-light);
`

export const Header = styled.header`
  display: flex;
  align-items: center;
  justify-content: space-between;

  > * {
    display: flex;

    &:first-child {
      padding: 0;
      margin: 0;
    }
  }
`

const Opportunity = ({ poolID }: OpportunityProps) => {
  const name = 'Conservative miner index'
  // just fuxing around
  const apy = `22.${poolID}2%`
  const tokenPrice = '1.325 FIL'
  return (
    <OppContainer>
      <DataContainer>
        <DataPoint>
          <p>Name</p>
          <h3>{name}</h3>
        </DataPoint>
        <DataPoint>
          <p>Current APY</p>
          <h3>{apy}</h3>
        </DataPoint>
        <DataPoint>
          <p>Current token price</p>
          <h3>{tokenPrice}</h3>
        </DataPoint>
      </DataContainer>
      <ButtonV2>&gt;</ButtonV2>
    </OppContainer>
  )
}

type OpportunityProps = {
  poolID: number
}

Opportunity.propTypes = {
  poolID: PropTypes.number.isRequired
}

const OpportunitiesWrapper = styled(ShadowBox)`
  margin-top: ${space()};
  width: fit-content;

  > header:first-child {
    margin-bottom: 0;
  }
`

export const Opportunities = ({ opportunities }: OpportunitiesProps) => {
  return (
    <OpportunitiesWrapper>
      <Header>
        <h2>Opportunities</h2>
      </Header>
      {opportunities.map((poolID) => (
        <Opportunity key={poolID} poolID={poolID} />
      ))}
    </OpportunitiesWrapper>
  )
}

type OpportunitiesProps = {
  opportunities: number[]
}
