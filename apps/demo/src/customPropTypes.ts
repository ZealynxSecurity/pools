import { FILECOIN_NUMBER_PROPTYPE } from '@glif/react-components'
import { arrayOf, number, string, shape } from 'prop-types'

export const POOL_PROP_TYPE = shape({
  id: number.isRequired,
  address: string.isRequired,
  name: string.isRequired,
  exchangeRate: FILECOIN_NUMBER_PROPTYPE.isRequired,
  interestRate: FILECOIN_NUMBER_PROPTYPE.isRequired
})

export const POOLS_PROP_TYPE = arrayOf(POOL_PROP_TYPE)
