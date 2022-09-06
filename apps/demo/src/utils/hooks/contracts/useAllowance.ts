import { FilecoinNumber } from '@glif/filecoin-number'
import { useContractRead } from 'wagmi'

import contractDigest from '../../../../generated/contractDigest.json'
const { WFIL } = contractDigest

export const useAllowance = (
  address: string,
  spender: string
): { allowance: FilecoinNumber; loading: boolean; error: Error } => {
  const { data, isLoading, error } = useContractRead({
    addressOrName: WFIL.address,
    contractInterface: WFIL.abi,
    functionName: 'allowance',
    enabled: !!address && !!spender,
    args: [address, spender]
  })

  if (data) {
    return {
      allowance: new FilecoinNumber(data.toString(), 'attofil'),
      error: null,
      loading: false
    }
  }

  return { allowance: new FilecoinNumber(0, 'fil'), loading: isLoading, error }
}
