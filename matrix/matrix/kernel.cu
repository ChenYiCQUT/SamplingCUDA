
#include "device_launch_parameters.h"
// CUDA runtime
#include <cuda_runtime.h>
#include <cublas_v2.h>

// CUDA and CUBLAS functions
//#include <helper_functions.h>
//#include <helper_cuda.h>
//#include <helper_string.h>
#include <stdio.h>
#include "setMatrix.h"
typedef struct {
	int width;
	int height;
	int stride;
	float *elements;
} Matrix_;
#define IDX2C(i,j,ld) (((j)*(ld))+(i));

cudaError_t addWithCuda(int *c, const int *a, const int *b, unsigned int size);
// cudaError_t multiMatriWithCuda(float *c, float *a, float *b, int widthA, int heightA, int widthB, int heightB,);

__global__ void addKernel(int *c, const int *a, const int *b)
{
	int i = threadIdx.x;
	c[i] = a[i] + b[i];
}

template<int BLOCK_SIZE>
__global__ void kaisaiMatrixComputation(float *b, float *a){
	int bx = blockIdx.x;
	//int by = blockIdx.y;

	// Thread index 
	int tx = threadIdx.x;
	//int ty = threadIdx.y;

	float Csub = 0;
	// Declaration of the shared memory array as used to store the sum-matrix of A
	__shared__ float As[BLOCK_SIZE];

	As[tx] = a[bx*BLOCK_SIZE + tx];
	Csub = expf(-1*As[tx]);
	b[bx*BLOCK_SIZE + tx] = Csub;
	return;
}

template<int BLOCK_SIZE>
__global__ void elementWiseDIV(float *c, float *a, float* b){
	int bx = blockIdx.x;
	//int by = blockIdx.y;

	// Thread index 
	int tx = threadIdx.x;
	//int ty = threadIdx.y;

	float Csub = 0;

	// Declaration of the shared memory array as used to store the sum-matrix of A
	__shared__ float As[BLOCK_SIZE];

	// Delcaration of the shared memory array as used to store the sub-matrix of B;
	__shared__ float Bs[BLOCK_SIZE];

	As[tx] = a[bx * BLOCK_SIZE + tx];
	Bs[tx] = b[bx * BLOCK_SIZE + tx];

	if (Bs[tx] > 0 && Bs[tx] < 0.000001){
		Bs[tx] = 0.000001;
	}
	else if (Bs[tx] < 0 && Bs[tx] > -0.000001){
		Bs[tx] = -0.000001;
	}
	c[bx * BLOCK_SIZE + tx] = As[tx] / Bs[tx];

	return;

}

template<int BLOCK_SIZE>
__global__ void distancePointToPointCUDA(float *c, float *a, float *b, int hA, int wA, int hB, int wB)
{
	// Block index
	int bx = blockIdx.x;
	int by = blockIdx.y;

	// Thread index 
	int tx = threadIdx.x;
	int ty = threadIdx.y;

	// index of the first sub-matrix of A processed by the block
	//	int a_begin = BLOCK_SIZE * bx;

	// index of the last sub-matrix of A processed by the block
	//	int a_end = a_begin +  BLOCK_SIZE - 1;

	// Step size used to iterate through the sub-matrices of A
	//	int a_step = BLOCK_SIZE;

	// Index of the first sub-matrix of B processed by the block
	//	int b_begin =  BLOCK_SIZE * by;

	// Index of the last sub-matrix of B proceesed by the block
	//	int b_end = b_begin +  BLOCK_SIZE - 1;

	// Step size used to iterate through the sub-matrices of B
	//	int b_step = BLOCK_SIZE;

	// Csub is used to store the element of the block sub-matrix
	// that is computed by the thread
	float Csub = 0;

	//const int B = wA;

	// Declaration of the shared memory array as used to store the sum-matrix of A
	__shared__ float As[2];

	// Delcaration of the shared memory array as used to store the sub-matrix of B;
	__shared__ float Bs[BLOCK_SIZE * 2];

	// Load the matrices from device memroy 
	// to shared memory; each thread loads 
	// one element of each matrix

#pragma unroll

	for (int i = 0; i < wA; i++){
		As[i] = a[bx * wA + i];

	}

#pragma unroll

	for (int i = 0; i < wA;i++){
		    Bs[ty * wA + i] = b[by * BLOCK_SIZE * wB + ty * wB + i];
	}
	
	// Synchronize to make sure the matrices are loaded

	__syncthreads();

#pragma unroll
	for (int i = 0; i < wA; i++){
		float dif_ = As[i] - Bs[ty * wA + i];
			Csub += dif_ * dif_;		
	}

	// Synchronized to make sure that the preceeding 
	// computation is done 

	__syncthreads();
	// Write the block sub- matrix to device memory;
	// eahc thread writes one element

	int c_line = bx ;
	int c_col =  by * BLOCK_SIZE + ty;
	c[c_line * hB + c_col] = Csub;	
}

int distanceCompuation(int block_size, dim3 &dimsA, dim3 &dimsB, float *matrix_A, float *matrix_B, float *matrix_C, float *matrix_D);

int initCuda(){
	int devID = 0;

	cudaSetDevice(devID);

	cudaError_t error;
	cudaDeviceProp deviceProp;
	error = cudaGetDevice(&devID);

	if (error != cudaSuccess){
		printf("cudaGetDevice returned error %s (code %d), line (%d)\n", cudaGetErrorString(error), error, __LINE__);
	}

	error = cudaGetDeviceProperties(&deviceProp, devID);

	if (deviceProp.computeMode == cudaComputeModeProhibited){
		fprintf(stderr, "Error: device is runing in <Compute Mode Prohibited>, no threads can use ::cudaSetDevice().\n");
		exit(EXIT_SUCCESS);
	}

	if (error != cudaSuccess){
		printf("cudaGetDeviceProperties returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);

	}
	else{
		printf("GPU Device %d: \"%s\" with compute capability %d.%d\n\n", devID, deviceProp.name, deviceProp.major, deviceProp.minor);
	}

	// Use a larger block size for Fermi and above
	int block_size = deviceProp.major < 2 ? 16 : 32;
	return block_size;
}

int main(int argc, char *argv[])
{


	const int arraySize = 5;
	const int a[arraySize] = { 1, 2, 3, 4, 5 };
	const int b[arraySize] = { 10, 20, 30, 40, 50 };
	int c[arraySize] = { 0 };
	int DIMENSIONS = 2;

	int num_samplingPoints; // �����������
	int width_originalPoints ; // ԭʼ������ĺ����������
	int height_originalPoints; // ԭʼ������������������
	int num_originalPoints; //
	float *m_samplingPoints; // �������λ�ã�
	float *m_originalPoints; // ԭʼ�ܶȺ�������ɢ�㣻
	float *m_samplingPointsDensity; // ��������ܶȣ�
	float *m_originalPointsDesntiy;

	num_samplingPoints = setNumSamplingPoint();
	width_originalPoints = setWidthOriginalPoint();
	height_originalPoints = setHeightOriginalPoint();
	num_originalPoints = width_originalPoints * height_originalPoints;

	m_samplingPoints = (float *)malloc(num_samplingPoints * DIMENSIONS * sizeof(float));
	m_originalPoints = (float *)malloc(width_originalPoints * height_originalPoints * DIMENSIONS * sizeof(float));
	m_samplingPointsDensity = (float *)malloc(num_samplingPoints * sizeof(float));
	m_originalPointsDesntiy = (float *)malloc(num_originalPoints * sizeof(float));

	setSamplingPoints(m_samplingPoints, num_samplingPoints, DIMENSIONS);
	setOriginalPoints(m_originalPoints, height_originalPoints, width_originalPoints, DIMENSIONS);
	setSamplingPointDensity(m_samplingPointsDensity, num_samplingPoints);
	setSamplingPointDensity(m_originalPointsDesntiy, num_originalPoints);	

	int block_size;

	// ��ʼ��CUDA
	block_size = initCuda();
	
	dim3 dims_sampling_points(num_samplingPoints, 2, 1);
	dim3 dims_original_points(width_originalPoints * height_originalPoints, 2, 1);
    // Add vectors in parallel.
	
	int _result = distanceCompuation(block_size, dims_sampling_points, dims_original_points, m_samplingPoints, m_originalPoints, m_samplingPointsDensity, m_originalPointsDesntiy);

	free(m_samplingPoints);
	free(m_originalPoints);
	free(m_originalPointsDesntiy);
	free(m_samplingPointsDensity);
	exit(_result);

	
}

int distanceCompuation(int block_size, dim3 &dimsA, dim3 &dimsB, float *matrix_A, float *matrix_B, float *matrix_C,float *matrix_D){
	// allocate host memory for original points and sampling points
	
	unsigned int size_A = dimsA.x * dimsA.y * dimsA.z;
	unsigned int mem_sizeA = sizeof(float) * size_A;
	float *h_A = matrix_A; // �����������

	unsigned int size_B = dimsB.x * dimsB.y * dimsB.z;
	unsigned int mem_sizeB = sizeof(float) * size_B;
	float  *h_B = matrix_B; // ������������꣬ԭʼͼ�������

	unsigned int size_samplingPoint = dimsA.x;
	unsigned int mem_sizeSamplingPoint = sizeof(float) * size_samplingPoint;
	float *h_samplingPointDensity = matrix_C;

	unsigned int size_originalPoint = dimsB.x;
	unsigned int mem_sizeOriginalPoint = sizeof(float) * size_originalPoint;
	float *h_originalPointDensity = matrix_D;

	unsigned int size_transportMatrix = dimsA.x * dimsB.x;
	unsigned int mem_sizeTransportMatrix = size_transportMatrix * sizeof(float);

	float *h_V = (float *)malloc(dimsB.x * sizeof(float));// ���㴫��ƻ�������v��
	for (int i = 0; i < dimsB.x; i++){
		*(h_V + i) = 1;
	}

	float *h_distanceMatrix;
	float *h_kasaiMatrix; // �������ĸ�˹����
	float *h_transportPlan;// = (float *)malloc(dimsA.x * dimsB.x * sizeof(float));

	// allocate device memory 
	float *d_A, *d_B, *d_distanceMatrix, *d_kasaiMatrix, *d_transportPlan, *d_U, *d_V; // device memory�еı���������d_U, d_V Ϊ�м����
	float *d_kasaiV, *d_kasaiU;
	float *d_samplingPointDensity, *d_originalPointDensity;
	float *d_diagUKasaiMatrix; /// ��ʱ����
	float *d_transportPlanDensity;///��ʱ����
	float *d_tempSamplPointCoordinate; // ��ʱ����
	cublasHandle_t handle;
	cublasStatus_t stat;
	cudaError_t error;

	
	stat = cublasCreate(&handle);
	if (stat != CUBLAS_STATUS_SUCCESS){
		printf("CUBLAS initialization failed\n");
		exit(EXIT_FAILURE);
	}
	
	error = cudaMalloc((void**)&d_A, mem_sizeA);

	if (error != cudaSuccess){
		printf("cudaMalloc d_A returned error %s (code %d), line(%d)\n", cudaGetErrorString, error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_B, mem_sizeB);

	if (error != cudaSuccess){
		printf("cudaMalloc d_B returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_distanceMatrix, mem_sizeTransportMatrix);
	if (error != cudaSuccess){
		printf("cudaMalloc d_distanceMatrix returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_kasaiMatrix, mem_sizeTransportMatrix);
	if (error != cudaSuccess){
		printf("cudaMalloc d_kasaiMatrix returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_U, mem_sizeSamplingPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_U returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_V, mem_sizeOriginalPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_V returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	
	error = cudaMalloc((void**)&d_kasaiV, mem_sizeSamplingPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_kasaiV returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_kasaiU, mem_sizeOriginalPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_kasaiU returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_samplingPointDensity, mem_sizeSamplingPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_samplingPointDensity returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_originalPointDensity, mem_sizeOriginalPoint);
	if (error != cudaSuccess){
		printf("cudaMalloc d_originalPointDensity returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_diagUKasaiMatrix, mem_sizeTransportMatrix);
	if (error != cudaSuccess){
		printf("cudaMalloc d_diagUKasaiMatrix returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_transportPlan, mem_sizeTransportMatrix);
	if (error != cudaSuccess){
		printf("cudaMalloc d_transportPlan returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_transportPlanDensity, mem_sizeTransportMatrix);
	if (error != cudaSuccess){
		printf("cudaMalloc d_transportPlanDensity returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMalloc((void**)&d_tempSamplPointCoordinate, mem_sizeA);
	if (error != cudaSuccess){
		printf("cudaMalloc d_tempSamplPointCoordinate returned error %s(code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	// copy host memory to device
	error = cudaMemcpy(d_A, h_A, mem_sizeA, cudaMemcpyHostToDevice);
	if (error != cudaSuccess){
		printf("cudaMemcpy (d_A, h_A) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMemcpy(d_B, h_B, mem_sizeB, cudaMemcpyHostToDevice);
	if (error != cudaSuccess){
		printf("cudaMemcpy (d_B, h_B) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMemcpy(d_V, h_V, mem_sizeOriginalPoint, cudaMemcpyHostToDevice);
	if (error != cudaSuccess){
		printf("cudaMemcpy (d_V, h_V) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMemcpy(d_samplingPointDensity, h_samplingPointDensity, mem_sizeSamplingPoint, cudaMemcpyHostToDevice);
	if (error != cudaSuccess){
		printf("cudaMemcpy (d_samplingPointDensity, h_samplingPointDensity) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMemcpy(d_originalPointDensity, h_originalPointDensity, mem_sizeOriginalPoint, cudaMemcpyHostToDevice);
	if (error != cudaSuccess){
		printf("cudaMemcpy (d_originalPointDensity, h_originalPointDensity) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

   // ����event
	cudaEvent_t start;
	error = cudaEventCreate(&start);

	if (error != cudaSuccess){
		fprintf(stderr, "Failed to create start event (error code %s)!\n", cudaGetErrorString(error));
		exit(EXIT_FAILURE);
	}
	cudaEvent_t stop;
	error = cudaEventCreate(&stop);

	if (error != cudaSuccess){
		fprintf(stderr, "Failed to create stop event (error code %s)!\n", cudaGetErrorString(error));
		exit(EXIT_FAILURE);
	}

	// Record the start event
	error = cudaEventRecord(start, NULL);

	if (error != cudaSuccess){
		fprintf(stderr, " Failed to record start evern (error code %s)! \n", cudaGetErrorString(error));
		exit(EXIT_FAILURE);
	}

	// Setup execution parameters
	block_size = 4;
	dim3 threads(1, block_size, 1);
	dim3 grid(dimsA.x, dimsB.x / block_size, 1);
	
	// ����������
	if (block_size == 16){
		distancePointToPointCUDA<4> << <grid, threads >> >(d_distanceMatrix, d_A, d_B, dimsA.x, dimsA.y, dimsB.x, dimsB.y);
	}
	else{
		distancePointToPointCUDA<4> << <grid, threads >> >(d_distanceMatrix, d_A, d_B, dimsA.x, dimsA.y, dimsB.x, dimsB.y);
	}
	/// ����distancePointToPointCUDA�Ƿ���ȷ
	h_distanceMatrix = (float *)malloc(mem_sizeTransportMatrix);
	error = cudaMemcpy(h_distanceMatrix, d_distanceMatrix, mem_sizeTransportMatrix, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_distanceMatrix, d_distanceMatrix) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	// cpu ����������
	float *c_C = (float *)malloc(mem_sizeTransportMatrix);
	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsB.x; j++){
			float diff_x;
			float diff_y;
			diff_x = *(h_A + i * dimsA.y) - *(h_B + j*dimsB.y);
			diff_y = *(h_A + i * dimsA.y + 1) - *(h_B + j*dimsB.y + 1);
			*(c_C + dimsB.x * i + j) = diff_x * diff_x + diff_y * diff_y;
		}
	}

	float diff_ = 0;
	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsB.x; j++)
			diff_ += abs(h_distanceMatrix[i * dimsB.x + j] - c_C[i*dimsB.x + j]);

	}
	printf("The difference distance computation between results of CPU and GPU is %f.\n", diff_);
	free(c_C);

	// ����Kasai����
	threads.x = block_size;
	threads.y = 1;
	threads.z = 1;
	grid.x = size_transportMatrix / threads.x;
	grid.y = 1;
	grid.z = 1;

	if (block_size == 16){
		kaisaiMatrixComputation<4> <<<grid, threads>> >(d_kasaiMatrix, d_distanceMatrix);
	}
	else{
		kaisaiMatrixComputation<4> <<<grid, threads >> >(d_kasaiMatrix, d_distanceMatrix);
	}
	/// �����Ƿ���ȷ
	h_kasaiMatrix = (float *)malloc(mem_sizeTransportMatrix);
	error = cudaMemcpy(h_kasaiMatrix, d_kasaiMatrix, mem_sizeTransportMatrix, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_distanceMatrix, d_distanceMatrix) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	float *check_kasaiMatrix = (float *)malloc(mem_sizeTransportMatrix);
	printf("kasaiMatrix on GPU and CPU \n ");
	for (int i = 0; i < size_transportMatrix; i++){
		check_kasaiMatrix[i] = exp(-h_distanceMatrix[i]);
		printf("%f  %f \n", h_kasaiMatrix[i], check_kasaiMatrix[i]);
		
	}
	diff_ = 0;
	for (int i = 0; i < size_transportMatrix; i++){
		diff_ += abs(check_kasaiMatrix[i]- h_kasaiMatrix[i]);
	}
	printf("The difference between kasai Matrix of CPU and GPU is %f.\n", diff_);
	free(check_kasaiMatrix);

	// ���㴫��ƻ�����
	 float alpha = 1.0 ;
	 float beta = 0.0 ;	 

	unsigned int _iter = 1;
	for (int i = 0; i < _iter; i++){	
		
		stat = cublasSgemv(handle, CUBLAS_OP_T, size_originalPoint, size_samplingPoint, &alpha, d_kasaiMatrix, size_originalPoint, d_V, 1, &beta, d_kasaiV,1);			
		if (stat != CUBLAS_STATUS_SUCCESS){
			printf("cublasSdot failed\n");
			exit(EXIT_FAILURE);
		}
		
		threads.x = 2; //block_size;
		threads.y = 1;
		threads.z = 1;
		grid.x = size_samplingPoint / threads.x;
		grid.y = 1;
		grid.z = 1;
		elementWiseDIV<2> << <grid, threads >> >(d_U, d_samplingPointDensity, d_kasaiV);
		stat = cublasSgemv(handle, CUBLAS_OP_N, size_originalPoint, size_samplingPoint, &alpha, d_kasaiMatrix, size_originalPoint, d_U, 1, &beta, d_kasaiU, 1);
		if (stat != CUBLAS_STATUS_SUCCESS){
			printf("cublasSdot failed\n");
			exit(EXIT_FAILURE);
		}
		threads.x = block_size;
		threads.y = 1;
		threads.z = 1;
		grid.x = size_originalPoint / threads.x;
		grid.y = 1;
		grid.z = 1;
		elementWiseDIV<4> << <grid, threads >> >(d_V, d_originalPointDensity, d_kasaiU);
	}
	
	float *h_kasaiV = (float *)malloc(size_samplingPoint);
	error = cudaMemcpy(h_kasaiV, d_kasaiV, mem_sizeSamplingPoint, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_kasaiV, d_kasaiV) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	
	float *h_U = (float *)malloc(mem_sizeSamplingPoint);
	error = cudaMemcpy(h_U, d_U, mem_sizeSamplingPoint, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_U, d_U) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	float *h_kasaiU = (float *)malloc(mem_sizeOriginalPoint);
	error = cudaMemcpy(h_kasaiU, d_kasaiU, mem_sizeOriginalPoint, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_kasaiU, d_kasaiU) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	error = cudaMemcpy(h_V, d_V, mem_sizeOriginalPoint, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_V, d_V) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	

	// �����ȷ��
	float *check_kasaiV = (float *)malloc(mem_sizeSamplingPoint);
	printf("kasaiV vector: GPU  CPU\n");
	for (int i = 0; i < size_samplingPoint; i++){
		float temp_ = 0;
		for (int j = 0; j < size_originalPoint; j++){
			temp_ += h_kasaiMatrix[i*size_originalPoint + j] * h_V[j];
		}
		check_kasaiV[i] = temp_;
		printf("KasaiV vector: %f  %f\n", h_kasaiV[i], check_kasaiV[i]);
	}
	diff_ = 0;
	for (int i = 0; i < size_samplingPoint; i++){
		diff_ += abs(h_kasaiV[i] - check_kasaiV[i]);
	}
	printf("The differenc of kasaiV vector: %f\n", diff_);
	free(check_kasaiV);

	float *check_U = (float *)malloc(mem_sizeSamplingPoint);
	printf("temp vector U: GPU    CPU\n");
	for (int i = 0; i < size_samplingPoint; i++){
		check_U[i] = h_samplingPointDensity[i] / h_kasaiV[i];
		printf("%f  %f\n", h_U[i], check_U[i]);
	}

	diff_ = 0;
	for (int i = 0; i < size_samplingPoint; i++){
		diff_ += abs(h_U[i] - check_U[i]);
	}
	printf("the difference of vector U: %f\n", diff_);

	free(check_U);


	float *check_kasaiU = (float *)malloc(mem_sizeOriginalPoint);
	printf("kasaiU vector: GPU  CPU\n");
	for (int i = 0; i < size_originalPoint; i++){
		float temp_ = 0;
		for (int j = 0; j < size_samplingPoint; j++){
			temp_ += h_kasaiMatrix[j*size_originalPoint + i] * h_U[j];
		}
		check_kasaiU[i] = temp_;
		printf("KasaiU vector: %f  %f\n", h_kasaiU[i], check_kasaiU[i]);
	}
	diff_ = 0;
	for (int i = 0; i < size_originalPoint; i++){
		diff_ += abs(h_kasaiU[i] - check_kasaiU[i]);
	}
	printf("The differenc of kasaiU vector: %f\n", diff_);
	free(check_kasaiU);


	float *check_V = (float *)malloc(mem_sizeOriginalPoint);
	printf("temp vector V: GPU    CPU\n");
	for (int i = 0; i < size_originalPoint; i++){
		check_V[i] = h_originalPointDensity[i] / h_kasaiU[i];
		printf("%f  %f\n", h_V[i], check_V[i]);
	}

	diff_ = 0;
	for (int i = 0; i < size_originalPoint; i++){
		diff_ += abs(h_V[i] - check_V[i]);
	}
	printf("the difference of vector V: %f\n", diff_);

	free(check_V);

	///���㴫��ƻ�����
	// ����cublasSdgmm�����Ծ���û��op���������������൱��ת�õļ��㣬 A= BCD   AT = DT CT BT (T��ʾת��)�ر�С��
	// �Դ��м������ d_transportMatrix ���󣬸պ���һ�� size_samplingPoint * size_originalPoint �Ҹպ��ǰ��������õľ���
	cublasSdgmm(handle, CUBLAS_SIDE_LEFT, size_originalPoint, size_samplingPoint, d_kasaiMatrix, size_originalPoint, d_V, 1, d_diagUKasaiMatrix, size_originalPoint);
	cublasSdgmm(handle, CUBLAS_SIDE_RIGHT, size_originalPoint, size_samplingPoint, d_diagUKasaiMatrix, size_originalPoint, d_U, 1, d_transportPlan, size_originalPoint);

	// �˶���ȷ��

	h_transportPlan = (float *)malloc(mem_sizeTransportMatrix);
	
	error = cudaMemcpy(h_transportPlan, d_transportPlan, mem_sizeTransportMatrix, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_transportPlan, d_transportPlan) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	float *check_transportPlan = (float *)malloc(mem_sizeTransportMatrix);
	float *ch_transportPlan = (float *)malloc(mem_sizeTransportMatrix);
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			ch_transportPlan[i*size_originalPoint + j] = h_U[i] * h_kasaiMatrix[i*size_originalPoint + j];
		}
	}
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			check_transportPlan[i*size_originalPoint + j] = ch_transportPlan[i*size_originalPoint + j] * h_V[j];
		}
	}

	printf("Transport plan matrix: GPU\n");
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			printf("  %f  ", h_transportPlan[i*size_originalPoint + j]);
		}
		printf("\n");
	}


	printf("Transport plan matrix: CPU\n");
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			printf("  %f  ", check_transportPlan[i*size_originalPoint + j]);
		}
		printf("\n");
	}

	free(check_transportPlan);
	free(ch_transportPlan);

	/// ��������ֵ����
	cublasSdgmm(handle, CUBLAS_SIDE_RIGHT, size_originalPoint, size_samplingPoint, d_transportPlan, size_originalPoint, d_samplingPointDensity, 1, d_transportPlanDensity, size_originalPoint);
	cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, dimsA.y, size_samplingPoint, size_originalPoint, &alpha, d_B, dimsA.y, d_transportPlanDensity, size_originalPoint, &beta, d_tempSamplPointCoordinate, dimsA.y);

	float *h_transportPlanDensity = (float *)malloc(mem_sizeTransportMatrix);
	error = cudaMemcpy(h_transportPlanDensity, d_transportPlanDensity, mem_sizeTransportMatrix, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_transportPlanDensity, d_transportPlanDensity) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}
	
	float *h_tempSamplPointCoordinate = (float *)malloc(mem_sizeA);
	error = cudaMemcpy(h_tempSamplPointCoordinate, d_tempSamplPointCoordinate, mem_sizeA, cudaMemcpyDeviceToHost);
	if (error != cudaSuccess){
		printf("cudaMemcpy (h_tempSamplPointCoordinate, d_tempSamplPointCoordinate) returned error %s (code %d), line(%d)\n", cudaGetErrorString(error), error, __LINE__);
		exit(EXIT_FAILURE);
	}

	// �˶���ȷ��
	float *h_transportPlanDensityT = (float *)malloc(mem_sizeTransportMatrix);
	for (int i = 0; i < size_originalPoint; i++){
		for (int j = 0; j < size_samplingPoint; j++){
			h_transportPlanDensityT[j*size_originalPoint + i] = h_transportPlanDensity[i*size_samplingPoint + j];
		}
	}


	float *check_transportPlanDensity = (float *)malloc(mem_sizeTransportMatrix);
	float *check_tempSamplPointCoordinate = (float *)malloc(mem_sizeA);
	float *h_transportPlanT = (float *)malloc(mem_sizeTransportMatrix);
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			h_transportPlanT[j*size_samplingPoint +i] = h_transportPlan[i*size_originalPoint + j];
		}
	}
	for (int i = 0; i < size_originalPoint; i++){
		for (int j = 0; j < size_samplingPoint; j++){
			check_transportPlanDensity[i*size_samplingPoint + j] = h_transportPlanT[i*size_samplingPoint + j] * h_samplingPointDensity[j];
		}
	}

	printf("Tempt matrix h_transportPlanDensity: GPU   CPU\n");
	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			printf("  %f   ", h_transportPlanDensityT[i*size_originalPoint + j]);
		}
		printf("\n");
	}

	for (int i = 0; i < size_samplingPoint; i++){
		for (int j = 0; j < size_originalPoint; j++){
			printf("  %f   ", check_transportPlanDensity[i*size_originalPoint + j]);
		}
		printf("\n");
	}

	// CUBLAS handle
	
	stat = cublasDestroy(handle);
	if (stat != CUBLAS_STATUS_SUCCESS){
		printf("cublasDestroy failed\n");
		exit(EXIT_FAILURE);
	}	

	// Record the stop event
	error = cudaEventRecord(stop, NULL);
	if (error != cudaSuccess){
		fprintf(stderr, " Failed to record stop event ( error code %s)! \n", cudaGetErrorString(error));
	}

	// Wait for the stop event to complete
	error = cudaEventSynchronize(stop);

	if (error != cudaSuccess){
		fprintf(stderr, "Failed to synchronize on the stop event (error code %s)! \n", cudaGetErrorString(error));
		exit(EXIT_FAILURE);
	}
	
	float msecTotal = 0.0f;
	error = cudaEventElapsedTime(&msecTotal, start, stop);

	if (error != cudaSuccess){
		fprintf(stderr, "Failed to get time elapsed between events (error code %s)!\n", cudaGetErrorString(error));
		exit(EXIT_FAILURE);
	}
	
	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsA.y; j++){	
			printf("%f  ", h_A[j*dimsA.x + i]);
		}
		printf("\n");
	}

	for (int i = 0; i < dimsA.x * dimsA.y; i++){
		
			printf("%f  ", h_A[ i]);
		}
		printf("\n");

	
	for (int i = 0; i < dimsB.x; i++){
		for (int j = 0; j < dimsB.y; j++){		
			printf("%f  ", h_B[ i * dimsB.y + j]);
		}
		printf("\n");
	}

	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsB.x; j++){
	//		printf("%f  ", h_C[i*dimsB.x + j]);
		}
		printf("\n");
	}

	for (int i = 0; i < dimsB.x; i++){
		for (int j = 0; j < dimsB.y; j++){
//			printf("%f  ", h_D[i * dimsB.y + j]);
		}
		printf("\n");
	}
	
	// Check  the result
	/*
	float *c_C = (float *)malloc(mem_sizeC);
	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsB.x; j++){
			float diff_x;
			float diff_y;
			diff_x = *(h_A + i * dimsA.y) - *(h_B + j*dimsB.y );
			diff_y = *(h_A + i * dimsA.y + 1) - *(h_B + j*dimsB.y + 1);
			*(c_C + dimsB.x * i + j) = diff_x * diff_x + diff_y * diff_y;
		}
	}

	float diff_ = 0;
	for (int i = 0; i < dimsA.x; i++){
		for (int j = 0; j < dimsB.x; j++)
			diff_ += ( h_C[i * dimsB.x + j] - c_C[i*dimsB.x + j]) * (h_C[i * dimsB.x + j] - c_C[i*dimsB.x + j] );

	}
	*/

	//printf("The difference between results of CPU and GPU is %f.\n", diff_);

	//printf("The dot product of h_B is %f\n", result_);

	//Clean up memory
	//free(h_A);
	//free(h_B);
	//free(h_C);
	//free(h_D);
	free(h_transportPlan);
	cudaFree(d_A);
	cudaFree(d_B);
	//cudaFree(d_C);

	printf("\nNOTE: The CUDA Samples are not meant for performance measurements. Results may vary when GPU Boost is enabled.\n");

	// cudaDeviceReset causes the driver to clean up all state. While
	// not mandatory in normal operation, it is good practice.  It is also
	// needed to ensure correct operation when the application is being
	// profiled. Calling cudaDeviceReset causes all profile data to be
	// flushed before the application exits

	cudaDeviceReset();

	return EXIT_SUCCESS;

}


// set variables for distance compuation between points
void setVariableForDistanceComputation(){




	return;
}

// Helper function for using CUDA to add vectors in parallel.
cudaError_t addWithCuda(int *c, const int *a, const int *b, unsigned int size)
{
    int *dev_a = 0;
    int *dev_b = 0;
    int *dev_c = 0;
	int *dev_d = 0;
    cudaError_t cudaStatus;

    // Choose which GPU to run on, change this on a multi-GPU system.
    cudaStatus = cudaSetDevice(0);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
        goto Error;
    }

    // Allocate GPU buffers for three vectors (two input, one output)    .
    cudaStatus = cudaMalloc((void**)&dev_c, size * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed!");
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_a, size * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed!");
        goto Error;
    }

    cudaStatus = cudaMalloc((void**)&dev_b, size * sizeof(int));
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed!");
        goto Error;
    }

	cudaStatus = cudaMalloc((void**)&dev_d, size * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_a, a, size * sizeof(int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy failed!");
        goto Error;
    }

    cudaStatus = cudaMemcpy(dev_b, b, size * sizeof(int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy failed!");
        goto Error;
    }

    // Launch a kernel on the GPU with one thread for each element.
    addKernel<<<1, size>>>(dev_c, dev_a, dev_b);



	addKernel << <1, size >> >(dev_d, dev_c, dev_b);


    // Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
        goto Error;
    }
    
    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
        goto Error;
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(c, dev_d, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy failed!");
        goto Error;
    }

Error:
	
	cudaFree(dev_c);
    cudaFree(dev_a);
    cudaFree(dev_b);
    
    return cudaStatus;
}

/*
cudaError_t multiMatriWithCuda(float *c, float *a, float *b, int widthA, int heightA, int widthB, int heightB)
{
	float2 *dev_a = 0;
	float2 *dev_b = 0;
	float2 *dev_c = 0;
	
	cudaError_t cudaStatus;

	// Choose which GPU to run on, change this on a multi-GPU system.
	cudaStatus = cudaSetDevice(0);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
		goto Error;
	}

	// Allocate GPU buffers for three vectors (two input, one output)    .
	cudaStatus = cudaMalloc((void**)&dev_c, heightA * heightB * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}

	cudaStatus = cudaMalloc((void**)&dev_a, heightA * widthA * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}

	cudaStatus = cudaMalloc((void**)&dev_b, heightB * widthB * sizeof(int));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!");
		goto Error;
	}



	// Copy input vectors from host memory to GPU buffers.
	cudaStatus = cudaMemcpy(dev_a, a, widthA * heightA * sizeof(int), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}

	cudaStatus = cudaMemcpy(dev_b, b, widthB * heightB * sizeof(int), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}

	// Launch a kernel on the GPU with one thread for each element.
	

	// Check for any errors launching the kernel
	cudaStatus = cudaGetLastError();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
		goto Error;
	}

	// cudaDeviceSynchronize waits for the kernel to finish, and returns
	// any errors encountered during the launch.
	cudaStatus = cudaDeviceSynchronize();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		goto Error;
	}

	// Copy output vector from GPU buffer to host memory.
	cudaStatus = cudaMemcpy(c, dev_d, size * sizeof(int), cudaMemcpyDeviceToHost);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		goto Error;
	}

Error:
	cudaFree(dev_c);
	cudaFree(dev_a);
	cudaFree(dev_b);

	return cudaStatus;
}
*/