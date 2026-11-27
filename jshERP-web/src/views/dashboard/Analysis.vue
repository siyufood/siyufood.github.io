<template>
  <div style="margin: 12px 12px 0px;">
    <a-row :gutter="12" style="margin-bottom:12px">
      <a-col :md="6" :sm="12">
        <a-card :bordered="false" size="small">
          <a-statistic title="在库批次" :value="counts.total" suffix="个"/>
        </a-card>
      </a-col>
      <a-col :md="6" :sm="12">
        <a-card :bordered="false" size="small" style="background:#fffbe6">
          <a-statistic title="30 天内临期" :value="counts.within30" suffix="个" valueStyle="color:#d48806"/>
        </a-card>
      </a-col>
      <a-col :md="6" :sm="12">
        <a-card :bordered="false" size="small" style="background:#fff1f0">
          <a-statistic title="已过期" :value="counts.expired" suffix="个" valueStyle="color:#cf1322"/>
        </a-card>
      </a-col>
      <a-col :md="6" :sm="12">
        <a-card :bordered="false" size="small">
          <div style="font-size:14px;color:rgba(0,0,0,.45)">批次与效期管理</div>
          <a-button type="primary" size="small" icon="calendar" style="margin-top:8px"
                    @click="$router.push('/plugin/foodbatch')">进入批次台账</a-button>
        </a-card>
      </a-col>
    </a-row>
    <index-chart></index-chart>
  </div>
</template>

<script>
  import IndexChart from './IndexChart'
  import { crud } from '@/api/plugin'

  function daysLeft(dateStr) {
    if (!dateStr) return null
    const d = new Date(String(dateStr).replace(/-/g, '/'))
    if (isNaN(d.getTime())) return null
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    return Math.round((d.getTime() - today.getTime()) / 86400000)
  }

  export default {
    name: "Analysis",
    components: {
      IndexChart
    },
    data() {
      return {
        counts: { total: 0, within30: 0, expired: 0 }
      }
    },
    created() {
      this.loadBatchStat()
    },
    methods: {
      loadBatchStat() {
        crud.list({ table: 'jsh_food_batch', pageSize: 500 }).then(r => {
          const rows = ((r.data || {}).rows) || []
          let expired = 0, within30 = 0, total = 0
          rows.forEach(row => {
            if ((row.status || '在库') === '已出库') return
            total++
            const d = daysLeft(row.expire_date)
            if (d === null) return
            if (d < 0) expired++
            else if (d <= 30) within30++
          })
          this.counts = { total, within30, expired }
        }).catch(() => {})
      }
    }
  }
</script>
