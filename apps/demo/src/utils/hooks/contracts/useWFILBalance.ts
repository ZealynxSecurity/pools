import { FilecoinNumber } from '@glif/filecoin-number'
import { useCallback } from 'react'
import useSWR, { SWRConfiguration } from 'swr'
import { useProvider } from 'wagmi'

import contractDigest from '../../../../generated/contractDigest.json'
import { WFIL__factory } from '../../../../typechain'

const { WFIL } = contractDigest

export const useWFILBalance = (
  address: string,
  swrConfig?: SWRConfiguration
): {
  balance: FilecoinNumber
  loading: boolean
  error: Error
} => {
  const provider = useProvider()
  const fetcher = useCallback(
    async (_, address) => {
      const wFIL = WFIL__factory.connect(WFIL.address, provider)

      const balance = await wFIL.balanceOf(address)
      return new FilecoinNumber(balance.toString(), 'attofil')
    },
    [provider]
  )

  const { data, error } = useSWR<FilecoinNumber>(
    [provider, address],
    fetcher,
    swrConfig
  )

  return { balance: data, loading: !data && !error, error }
}
