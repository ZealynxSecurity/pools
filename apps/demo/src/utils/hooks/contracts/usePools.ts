import { useMemo } from 'react'
import { FilecoinNumber } from '@glif/filecoin-number'
import flatmap from 'lodash.flatmap'
import { useContractRead, useContractReads } from 'wagmi'
import contractDigest from '../../../../generated/contractDigest.json'
import { UseContractReadsConfig } from 'wagmi/dist/declarations/src/hooks/contracts/useContractReads'

const { PoolFactory, SimpleInterestPool } = contractDigest

export type Pool = {
  id: string
  address: string
  name: string
  exchangeRate: FilecoinNumber
  interestRate: FilecoinNumber
  totalAssets: FilecoinNumber
}

export type UsePoolAddressesReturn = {
  pools: Pool[]
  isLoading: boolean
  error: Error | null
}

export const usePools = (): UsePoolAddressesReturn => {
  const {
    data: allPoolsLength,
    isLoading: allPoolsLengthLoading,
    error: allPoolsLengthError
  } = useContractRead({
    addressOrName: PoolFactory.address,
    contractInterface: PoolFactory.abi,
    functionName: 'allPoolsLength'
  })

  const poolContracts = useMemo<UseContractReadsConfig>(() => {
    const contracts = []
    if (!allPoolsLengthLoading && !allPoolsLengthError) {
      for (let i = 0; i < Number(allPoolsLength.toString()); i++) {
        contracts.push({
          addressOrName: PoolFactory.address,
          contractInterface: PoolFactory.abi,
          functionName: 'allPools',
          args: [i]
        })
      }
    }
    return { contracts }
  }, [allPoolsLength, allPoolsLengthLoading, allPoolsLengthError])

  const {
    data: poolAddrs,
    isLoading: poolsLoading,
    error: poolsError
  } = useContractReads(poolContracts)

  const poolMetadataContracts = useMemo<UseContractReadsConfig>(() => {
    if (poolsError || poolsLoading) {
      return { contracts: [] }
    }

    const contracts = flatmap(poolAddrs, (address) => {
      return [
        {
          addressOrName: address.toString(),
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'name'
        },
        {
          addressOrName: address.toString(),
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'previewDeposit',
          args: [1]
        },
        {
          addressOrName: address.toString(),
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'interestRate'
        },
        {
          addressOrName: address.toString(),
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'totalAssets'
        }
      ]
    })
    return { contracts }
  }, [poolAddrs, poolsLoading, poolsError])

  const { data, isLoading, error } = useContractReads(poolMetadataContracts)
  // this is to help us make sense of the return data from `useContractReads`
  // each pool contract has a call to "name" and to "previewDeposit"
  const CONTRACT_READS_PER_POOL = 4
  const pools = useMemo(() => {
    if (error || isLoading) return []
    if (!data) return []

    const byPool: Pool[] = []

    for (let i = 0; i < poolAddrs.length; i++) {
      const indexes = []
      for (let j = 0; j < CONTRACT_READS_PER_POOL; j++) {
        indexes.push(i * CONTRACT_READS_PER_POOL + j)
      }
      const pool: Pool = {
        address: poolAddrs[i].toString(),
        id: i.toString(),
        name: data[indexes[0]].toString(),
        exchangeRate: new FilecoinNumber(data[indexes[1]].toString(), 'fil'),
        interestRate: new FilecoinNumber(
          data[indexes[2]].toString(),
          'attofil'
        ),
        totalAssets: new FilecoinNumber(data[indexes[3]].toString(), 'attofil')
      }
      byPool.push(pool)
    }

    return byPool
  }, [data, poolAddrs, error, isLoading])
  if (!!error) {
    return {
      pools: [],
      isLoading: false,
      error
    }
  } else if (isLoading) {
    return {
      pools: [],
      isLoading: true,
      error: null
    }
  }

  return {
    pools,
    error: null,
    isLoading: false
  }
}

export const usePool = (poolID: string): Pool => {
  const { pools } = usePools()
  return useMemo(() => {
    if (pools.length > 0 && !!poolID) {
      return pools[poolID as string]
    }

    return {
      id: '',
      address: '',
      name: '',
      exchangeRate: new FilecoinNumber('0', 'fil'),
      interestRate: new FilecoinNumber('0', 'fil'),
      totalAssets: new FilecoinNumber('0', 'fil')
    }
  }, [pools, poolID])
}
