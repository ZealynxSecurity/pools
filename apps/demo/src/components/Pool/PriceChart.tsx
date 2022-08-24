import styled from 'styled-components'
import PropTypes from 'prop-types'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip
} from 'chart.js'
import { Line } from 'react-chartjs-2'
import { space } from '@glif/react-components'
import { random2DecimalFloat } from '../../utils'

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip
)

export const options = {
  responsive: true,
  plugins: {
    title: {
      display: false,
      text: 'Pool token price chart'
    }
  }
}

const labels = ['January', 'February', 'March', 'April', 'May', 'June', 'July']

export const data = {
  labels,
  datasets: [
    {
      label: 'Dataset 1',
      data: labels.map(() => random2DecimalFloat(1, 2)),
      borderColor: 'rgb(255, 99, 132)',
      backgroundColor: 'rgba(255, 99, 132, 0.5)'
    }
  ]
}

const PriceChartWrapper = styled.div`
  margin-top: ${space()};

  > h2 {
    padding: 0;
    margin-top: ${space()};
    margin-bottom: ${space()};
    color: var(--purple-medium);
  }
`

export function PriceChart(_: { poolID: number }) {
  return (
    <PriceChartWrapper>
      <Line options={options} data={data} width={800} height={200} />
    </PriceChartWrapper>
  )
}

PriceChart.propTypes = {
  poolID: PropTypes.number.isRequired
}
