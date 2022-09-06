import { ButtonV2, navigate, ShadowBox, space } from '@glif/react-components'
import styled from 'styled-components'
import { useRouter } from 'next/router'

import { DataPoint } from '../generic'
import { PAGE } from '../../../constants'
import { Pool } from '../../utils'
import { POOLS_PROP_TYPE, POOL_PROP_TYPE } from '../../customPropTypes'

const OppContainer = styled.div`
  width: 100%;
  justify-self: center;
  align-self: center;
  align-items: center;
  display: flex;
  flex-direction: row;

  > button {
    border: none;
    padding: 0;
    margin: 0;
    height: fit-content;
  }
`

const DataContainer = styled.div`
  width: 100%;
  display: flex;
  flex-direction: row;
  justify-content: space-around;
  flex-grow: 1;

  border-bottom: 1px solid var(--gray-light);

  > button {
  }
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

const Opportunity = ({ pool }: OpportunityProps) => {
  const router = useRouter()

  return (
    <OppContainer>
      <DataContainer>
        <DataPoint>
          <p>Name</p>
          <h3>{pool.name}</h3>
        </DataPoint>
        <DataPoint>
          <p>Current APY</p>
          <h3>{pool.interestRate.toFil()}%</h3>
        </DataPoint>
        <DataPoint>
          <p>Price per share</p>
          <h3>{pool.exchangeRate.toFil()} FIL</h3>
        </DataPoint>
      </DataContainer>
      <ButtonV2
        onClick={() =>
          navigate(router, {
            pageUrl: PAGE.POOL,
            params: {
              id: pool.id
            }
          })
        }
      >
        &gt;
      </ButtonV2>
    </OppContainer>
  )
}

type OpportunityProps = {
  pool: Pool
}

Opportunity.propTypes = {
  pool: POOL_PROP_TYPE.isRequired
}

const OpportunitiesWrapper = styled(ShadowBox)`
  margin-top: ${space()};
  width: fit-content;

  > header:first-child {
    margin-bottom: 0;
  }
`

export const Opportunities = ({ pools }: OpportunitiesProps) => {
  return pools.length > 0 ? (
    <>
      <br />
      <OpportunitiesWrapper>
        <Header>
          <h2>Opportunities</h2>
        </Header>
        {pools.map((pool) => (
          <Opportunity key={pool.address} pool={pool} />
        ))}
      </OpportunitiesWrapper>
    </>
  ) : (
    <div>Loading...</div>
  )
}

type OpportunitiesProps = {
  pools: Pool[]
}

Opportunities.propTypes = {
  pools: POOLS_PROP_TYPE.isRequired
}
