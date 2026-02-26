import { useState } from 'react'
import { Upload, Button, message, Card, Progress, Space, Typography, Row, Col } from 'antd'
import {
  InboxOutlined,
  FileTextOutlined,
  FileExcelOutlined,
  FilePptOutlined,
  MergeCellsOutlined,
  ScissorOutlined,
  ArrowLeftOutlined
} from '@ant-design/icons'
import axios from 'axios'
import './App.css'

const { Dragger } = Upload
const { Title, Text } = Typography

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api/v1'

// 功能列表配置
const FEATURES = [
  {
    id: 'pdf2word',
    title: 'PDF 转 Word',
    description: '将 PDF 文档转换为可编辑的 Word 文件',
    icon: <FileTextOutlined style={{ fontSize: 48, color: '#1890ff' }} />,
    accept: '.pdf',
    buttonText: '开始转换'
  },
  {
    id: 'pdf2excel',
    title: 'PDF 转 Excel',
    description: '从 PDF 中提取表格数据到 Excel',
    icon: <FileExcelOutlined style={{ fontSize: 48, color: '#52c41a' }} />,
    accept: '.pdf',
    buttonText: '开始转换'
  },
  {
    id: 'pdf2ppt',
    title: 'PDF 转 PPT',
    description: '将 PDF 转换为 PowerPoint 演示文稿',
    icon: <FilePptOutlined style={{ fontSize: 48, color: '#fa8c16' }} />,
    accept: '.pdf',
    buttonText: '开始转换'
  },
  {
    id: 'merge',
    title: 'PDF 合并',
    description: '将多个 PDF 文件合并为一个',
    icon: <MergeCellsOutlined style={{ fontSize: 48, color: '#722ed1' }} />,
    accept: '.pdf',
    buttonText: '开始合并',
    multiple: true
  },
  {
    id: 'split',
    title: 'PDF 拆分',
    description: '将一个 PDF 文件拆分为多个',
    icon: <ScissorOutlined style={{ fontSize: 48, color: '#eb2f96' }} />,
    accept: '.pdf',
    buttonText: '开始拆分'
  }
]

function App() {
  const [currentFeature, setCurrentFeature] = useState(null)
  const [file, setFile] = useState(null)
  const [files, setFiles] = useState([])
  const [converting, setConverting] = useState(false)
  const [progress, setProgress] = useState(0)
  const [result, setResult] = useState(null)

  // 生成客户端 ID
  const getClientId = () => {
    let clientId = localStorage.getItem('client_id')
    if (!clientId) {
      clientId = 'client_' + Math.random().toString(36).substr(2, 9)
      localStorage.setItem('client_id', clientId)
    }
    return clientId
  }

  // 处理文件上传
  const handleUpload = async (taskType) => {
    if (!file) {
      message.error('请先选择 PDF 文件')
      return
    }

    setConverting(true)
    setProgress(0)
    setResult(null)

    try {
      // 1. 上传文件到服务器
      const formData = new FormData()
      formData.append('file', file)

      const uploadRes = await axios.post(`${API_BASE_URL}/upload`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: (progressEvent) => {
          const percentCompleted = Math.round((progressEvent.loaded * 50) / progressEvent.total)
          setProgress(percentCompleted)
        }
      })

      const fileKey = uploadRes.data.file_key
      setProgress(50)

      // 2. 创建转换任务
      const taskRes = await axios.post(`${API_BASE_URL}/tasks`, {
        file_key: fileKey,
        task_type: taskType,
        file_name: file.name,
        file_size: file.size,
        client_id: getClientId()
      })

      const taskId = taskRes.data.task_id

      // 3. 轮询任务状态
      const pollTask = async () => {
        const statusRes = await axios.get(`${API_BASE_URL}/tasks/${taskId}`)
        const status = statusRes.data.status

        if (status === 'completed') {
          setProgress(100)
          setResult(statusRes.data)
          message.success('转换完成！')
          setConverting(false)
        } else if (status === 'failed') {
          message.error('转换失败: ' + statusRes.data.error_msg)
          setConverting(false)
        } else if (status === 'processing') {
          setProgress(prev => Math.min(prev + 10, 90))
          setTimeout(pollTask, 2000)
        } else {
          setTimeout(pollTask, 2000)
        }
      }

      setTimeout(pollTask, 2000)

    } catch (error) {
      console.error('Upload error:', error)

      if (error.response?.status === 402) {
        message.warning('文件过大，需要付费解锁')
      } else {
        message.error('上传失败: ' + (error.response?.data?.detail || error.message))
      }

      setConverting(false)
    }
  }

  const uploadProps = {
    name: 'file',
    multiple: currentFeature?.multiple || false,
    accept: currentFeature?.accept || '.pdf',
    beforeUpload: (file) => {
      if (file.type !== 'application/pdf') {
        message.error('只支持 PDF 文件')
        return Upload.LIST_IGNORE
      }

      if (file.size > 500 * 1024 * 1024) {
        message.error('文件过大，最大支持 500MB')
        return Upload.LIST_IGNORE
      }

      if (currentFeature?.multiple) {
        setFiles(prev => [...prev, file])
        message.success(`已添加: ${file.name}`)
      } else {
        setFile(file)
        message.success(`已选择: ${file.name}`)
      }
      return false
    }
  }

  // 返回首页
  const goBack = () => {
    setCurrentFeature(null)
    setFile(null)
    setFiles([])
    setConverting(false)
    setProgress(0)
    setResult(null)
  }

  // 选择功能
  const selectFeature = (feature) => {
    setCurrentFeature(feature)
    setFile(null)
    setFiles([])
    setResult(null)
  }

  // 渲染功能选择页面
  const renderFeatureSelection = () => (
    <div style={{ marginTop: 32 }}>
      <Title level={2} style={{ textAlign: 'center', marginBottom: 40 }}>
        选择您需要的功能
      </Title>
      <Row gutter={[24, 24]}>
        {FEATURES.map(feature => (
          <Col xs={24} sm={12} md={8} key={feature.id}>
            <Card
              hoverable
              onClick={() => selectFeature(feature)}
              style={{ textAlign: 'center', height: '100%' }}
            >
              <div style={{ padding: '20px 0' }}>
                {feature.icon}
                <Title level={4} style={{ marginTop: 16, marginBottom: 8 }}>
                  {feature.title}
                </Title>
                <Text type="secondary">{feature.description}</Text>
              </div>
            </Card>
          </Col>
        ))}
      </Row>
    </div>
  )

  // 渲染转换页面
  const renderConversionPage = () => (
    <div style={{ marginTop: 32 }}>
      <Button
        icon={<ArrowLeftOutlined />}
        onClick={goBack}
        style={{ marginBottom: 16 }}
      >
        返回首页
      </Button>

      <Card>
        <Title level={3}>{currentFeature.title}</Title>
        <Text type="secondary">{currentFeature.description}</Text>

        <div style={{ marginTop: 24 }}>
          <Dragger {...uploadProps} disabled={converting}>
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">
              {currentFeature.multiple ? '点击或拖拽 PDF 文件到此区域（可选择多个）' : '点击或拖拽 PDF 文件到此区域'}
            </p>
            <p className="ant-upload-hint">
              支持{currentFeature.multiple ? '多个' : '单个'}文件上传，每个文件最大 500MB
            </p>
          </Dragger>

          {currentFeature.multiple && files.length > 0 && (
            <div style={{ marginTop: 16 }}>
              <Text strong>已选择 {files.length} 个文件：</Text>
              <ul>
                {files.map((f, idx) => (
                  <li key={idx}>{f.name}</li>
                ))}
              </ul>
            </div>
          )}

          {((file && !currentFeature.multiple) || (files.length > 0 && currentFeature.multiple)) && !converting && !result && (
            <div style={{ marginTop: 24, textAlign: 'center' }}>
              <Button
                type="primary"
                size="large"
                icon={currentFeature.icon}
                onClick={() => handleUpload(currentFeature.id)}
              >
                {currentFeature.buttonText}
              </Button>
            </div>
          )}

          {converting && (
            <div style={{ marginTop: 24 }}>
              <Progress percent={progress} status="active" />
              <Text type="secondary">正在处理中，请稍候...</Text>
            </div>
          )}

          {result && (
            <Card style={{ marginTop: 24 }} type="inner">
              <Title level={4}>处理完成！</Title>
              <Text>文件名: {result.file_name}</Text>
              <br />
              <Button
                type="primary"
                style={{ marginTop: 16 }}
                href={result.download_url}
                download
              >
                下载文件
              </Button>
              <Text type="secondary" style={{ marginLeft: 16 }}>
                文件将在 1 小时后自动删除
              </Text>
              <br />
              <Button
                style={{ marginTop: 16 }}
                onClick={goBack}
              >
                继续处理其他文件
              </Button>
            </Card>
          )}
        </div>
      </Card>
    </div>
  )

  return (
    <div className="app">
      <div className="container">
        <Title level={1}>PDFShift</Title>
        <Text type="secondary">在线 PDF 转换工具 - 免费、快速、安全</Text>

        {!currentFeature ? renderFeatureSelection() : renderConversionPage()}

        <div className="footer">
          <Text type="secondary">
            © 2026 PDFShift | <a href="/privacy">隐私政策</a> | <a href="/terms">用户协议</a>
          </Text>
        </div>
      </div>
    </div>
  )
}

export default App
