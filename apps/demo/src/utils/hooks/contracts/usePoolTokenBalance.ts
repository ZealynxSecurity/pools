import { FilecoinNumber } from '@glif/filecoin-number'
import { useMemo } from 'react'
import { useContractRead, useContractReads } from 'wagmi'
import { usePools } from './usePools'
import contractDigest from '../../../../generated/contractDigest.json'

const { SimpleInterestPool } = contractDigest

export const useAllPoolTokenBalances = (
  address: string
): Record<string, FilecoinNumber> => {
  const { pools } = usePools()
  const contracts = useMemo(() => {
    if (!address) return { contracts: [], enabled: false }
    return {
      contracts: pools.map((p) => {
        return {
          addressOrName: p.address,
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'balanceOf',
          args: [address],
          cacheTime: 100000
        }
      })
    }
  }, [address, pools])

  const { data } = useContractReads(contracts)
  if (!data) return null

  return pools.reduce((accum, pool) => {
    const poolID = pool.id.toString()
    accum[poolID] = new FilecoinNumber(data[poolID].toString(), 'attofil')
    return accum
  }, {})
}

export const usePoolTokenBalance = (
  poolID: string,
  address: string
): { balance: FilecoinNumber; loading: boolean; error: Error } => {
  const { pools } = usePools()

  const contract = useMemo(() => {
    if (pools.length > 0 && !!pools[poolID] && !!address) {
      return {
        addressOrName: pools[poolID].address,
        contractInterface: SimpleInterestPool[0].abi,
        functionName: 'balanceOf',
        args: [address],
        cacheTime: 100000
      }
    }

    return {
      addressOrName: '',
      contractInterface: SimpleInterestPool[0].abi,
      functionName: 'balanceOf',
      args: [],
      enabled: false
    }
  }, [address, poolID, pools])

  const { data, isLoading, error } = useContractRead(contract)

  if (data) {
    return {
      balance: new FilecoinNumber(data.toString(), 'attofil'),
      loading: isLoading,
      error
    }
  }
  return {
    balance: new FilecoinNumber(0, 'attofil'),
    loading: isLoading,
    error
  }
}
