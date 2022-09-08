import { FilecoinNumber } from '@glif/filecoin-number'
import { Signer } from 'ethers'
import { useCallback } from 'react'
import useSWR, { SWRConfiguration } from 'swr'
import { useSigner } from 'wagmi'
import { SimpleInterestPool__factory } from '../../../../typechain'
import {
  LoanStruct,
  LoanStructOutput
} from '../../../../typechain/SimpleInterestPool'

export type Loan = {
  [Property in keyof LoanStruct]: FilecoinNumber
}

export type LoanBalance = {
  penalty: FilecoinNumber
  bal: FilecoinNumber
}

const pluckKeys = (l: LoanStructOutput): Array<keyof LoanStruct> => {
  // the LoanStructOutput has numbered keys that are identical to the named keys
  // this function strips the numbered keys and returns just the named keys
  return Object.keys(l).filter((k) => isNaN(Number(k))) as Array<
    keyof LoanStruct
  >
}

export const useLoan = (
  loanAgentAddr: string,
  poolAddress: string,
  swrConfig: SWRConfiguration = { refreshInterval: 10000 }
): { loan: Loan; balance: LoanBalance; error: Error } => {
  const { data: signer } = useSigner()
  const fetcher = useCallback(
    async (loanAgentAddr: string, poolAddr: string, signer: Signer) => {
      if (!loanAgentAddr || !signer) {
        return null
      }

      const pool = SimpleInterestPool__factory.connect(poolAddr, signer)
      const loan = await pool.getLoan(loanAgentAddr)
      const formattedLoan = pluckKeys(loan).reduce((accum, key) => {
        accum[key] = new FilecoinNumber(loan[key].toString(), 'attofil')
        return accum
      }, {}) as Loan

      const loanBal = await pool.loanBalance(loanAgentAddr)
      const balance: LoanBalance = {
        penalty: new FilecoinNumber(loanBal.penalty.toString(), 'attofil'),
        bal: new FilecoinNumber(loanBal.bal.toString(), 'attofil')
      }

      return { loan: formattedLoan, balance }
    },
    []
  )

  const { data, error } = useSWR(
    [loanAgentAddr, poolAddress, signer, 'loan'],
    fetcher,
    swrConfig
  )

  return { loan: data?.loan, balance: data?.balance, error }
}
