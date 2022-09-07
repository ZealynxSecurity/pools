import { FilecoinNumber } from '@glif/filecoin-number'
import { Dispatch, SetStateAction } from 'react'

export enum TransactTab {
  DEPOSIT = 'DEPOSIT',
  WITHDRAW = 'WITHDRAW'
}

export type TabsProps = {
  tab: TransactTab
  setTab: Dispatch<SetStateAction<TransactTab>>
}

export interface BaseFormProps {
  header: string
  subheader?: string
  inputLabel: string
  submitBtnText: string
  tokenName: string
  onSubmit: (amount: FilecoinNumber) => Promise<void>
  tab: TransactTab
  setTab: Dispatch<SetStateAction<TransactTab>>
  poolID: string
  exchangeRateLabel?: string
  exchangeRate?: FilecoinNumber
}
