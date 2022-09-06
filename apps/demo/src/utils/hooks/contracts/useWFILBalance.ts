import { FilecoinNumber } from '@glif/filecoin-number'
import { useContractRead } from 'wagmi'

import contractDigest from '../../../../generated/contractDigest.json'

const { WFIL } = contractDigest

export const useWFILBalance = (
  address: string
): {
  balance: FilecoinNumber
  loading: boolean
  error: Error
} => {
  const { data, isLoading, error } = useContractRead({
    addressOrName: WFIL.address,
    contractInterface: WFIL.abi,
    functionName: 'balanceOf',
    args: [address],
    enabled: !!address
  })

  if (data) {
    return {
      balance: new FilecoinNumber(data.toString(), 'attofil'),
      loading: false,
      error: null
    }
  }

  return {
    balance: new FilecoinNumber(0, 'attofil'),
    loading: isLoading,
    error
  }
}
