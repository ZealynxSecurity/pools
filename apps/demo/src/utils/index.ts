export const randomInt = (min, max) =>
  Math.floor(Math.random() * (max - min + 1) + min)

export const random2DecimalFloat = (min, max) =>
  `${randomInt(min, max)}.${randomInt(0, 100)}`
