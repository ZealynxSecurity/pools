import { useMemo } from 'react'
import PropTypes from 'prop-types'
import { ButtonV2, navigate, ShadowBox, space } from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import styled from 'styled-components'
import { useContractReads } from 'wagmi'

import { DataPoint } from '../generic'
import contractDigest from '../../../generated/contractDigest.json'
import { useRouter } from 'next/router'
import { PAGE } from '../../../constants'

const { SimpleInterestPool } = contractDigest

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

const Opportunity = ({ poolAddress }: OpportunityProps) => {
  const contracts = useMemo(() => {
    return [
      {
        addressOrName: poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'id'
      },
      {
        addressOrName: poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'name'
      },
      {
        addressOrName: poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'interestRate'
      },
      {
        addressOrName: poolAddress,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'previewDeposit',
        args: [1]
      }
    ]
  }, [poolAddress])

  const { data } = useContractReads({ contracts })

  const [id, name, interestRate, pricePerShare] = useMemo(() => {
    if (data) {
      return [
        data[0].toString(),
        data[1].toString(),
        new FilecoinNumber(data[2].toString(), 'attofil').times(100).toFil(),
        data[3].toString()
      ]
    }

    return []
  }, [data])

  const router = useRouter()

  return (
    <OppContainer>
      <DataContainer>
        <DataPoint>
          <p>Name</p>
          <h3>{name}</h3>
        </DataPoint>
        <DataPoint>
          <p>Current APY</p>
          <h3>{interestRate}%</h3>
        </DataPoint>
        <DataPoint>
          <p>Price per share</p>
          <h3>{pricePerShare} FIL</h3>
        </DataPoint>
      </DataContainer>
      <ButtonV2
        onClick={() =>
          navigate(router, {
            pageUrl: PAGE.POOL,
            params: {
              id
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
  poolAddress: string
}

Opportunity.propTypes = {
  poolAddress: PropTypes.string.isRequired
}

const OpportunitiesWrapper = styled(ShadowBox)`
  margin-top: ${space()};
  width: fit-content;

  > header:first-child {
    margin-bottom: 0;
  }
`

export const Opportunities = ({ poolAddrs }: OpportunitiesProps) => {
  return poolAddrs && poolAddrs.length > 0 ? (
    <>
      <br />
      <OpportunitiesWrapper>
        <Header>
          <h2>Opportunities</h2>
        </Header>
        {poolAddrs.map((poolAddress) => (
          <Opportunity key={poolAddress} poolAddress={poolAddress} />
        ))}
      </OpportunitiesWrapper>
    </>
  ) : (
    <div>Loading...</div>
  )
}

type OpportunitiesProps = {
  // pool addresses
  poolAddrs: string[]
}
