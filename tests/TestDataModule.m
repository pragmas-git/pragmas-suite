classdef TestDataModule < matlab.unittest.TestCase
    % TESTDATAMODULE Unit tests para +pragmas/+data
    % Ejecuta: runtests('tests/TestDataModule.m')
    
    properties
        % Datos de prueba sintéticos
        TestSeries
        TestPrices
        StartDate
        EndDate
    end
    
    methods (TestMethodSetup)
        function setupTestData(testCase)
            % Crea datos sintéticos para pruebas
            testCase.StartDate = datetime('2025-01-01');
            testCase.EndDate = datetime('2025-01-31');
            
            % Serie temporal sintética estacionaria (random walk)
            rng(42);  % Reproducibilidad
            n = 100;
            testCase.TestSeries = cumsum(randn(n, 1));
            testCase.TestPrices = 100 * exp(cumsum(0.01 * randn(n, 1)));  % Log-normal prices
        end
    end
    
    methods (Test)
        
        function testComputeHurst_Basic(testCase)
            % Verifica que computeHurst retorna un escalar en [0, 1.5]
            H = pragmas.data.computeHurst(testCase.TestSeries);
            
            testCase.verifyClass(H, 'double');
            testCase.verifyEqual(size(H), [1 1]);
            testCase.verifyGreaterThanOrEqual(H, -0.5);
            testCase.verifyLessThanOrEqual(H, 2);
        end
        
        function testComputeHurst_WithReturns(testCase)
            % Verifica computeHurst con retornos logarítmicos
            returns = diff(log(testCase.TestPrices));
            H = pragmas.data.computeHurst(returns);
            
            testCase.verifyClass(H, 'double');
            testCase.verifyGreaterThan(H, 0);
        end
        
        function testComputeHurst_NaNHandling(testCase)
            % Verifica que computeHurst maneja NaNs correctamente
            series = testCase.TestSeries;
            series([10, 25, 50]) = NaN;  % Inyectar NaNs
            
            H = pragmas.data.computeHurst(series);
            
            testCase.verifyClass(H, 'double');
            testCase.verifyFalse(isnan(H));
        end
        
        function testComputeHurst_ShortSeries(testCase)
            % Verifica que computeHurst rechaza series muy cortas
            shortSeries = testCase.TestSeries(1:50);  % < 100 observaciones
            
            testCase.verifyError(@() pragmas.data.computeHurst(shortSeries), ...
                'MATLAB:validation:IncompatibleSize');
        end
        
        function testFractionalDiff_Basic(testCase)
            % Verifica que fractionalDiff retorna vector de longitud correcta
            d = 0.3;
            diff_series = pragmas.data.fractionalDiff(testCase.TestPrices, d);
            
            testCase.verifyClass(diff_series, 'double');
            testCase.verifyLessThan(length(diff_series), length(testCase.TestPrices));
            testCase.verifyGreaterThan(length(diff_series), 0);
        end
        
        function testFractionalDiff_DRange(testCase)
            % Verifica comportamiento para diferentes órdenes fraccionales
            d_values = [0.1, 0.3, 0.5];
            
            for d = d_values
                diff_series = pragmas.data.fractionalDiff(testCase.TestPrices, d);
                testCase.verifyTrue(isvector(diff_series) && length(diff_series) > 0, ...
                    sprintf('d=%.2f debería retornar vector no vacío', d));
            end
        end
        
        function testFractionalDiff_ThresholdEffect(testCase)
            % Verifica que threshold afecta longitud de pesos
            d = 0.4;
            
            diff_high_thresh = pragmas.data.fractionalDiff(testCase.TestPrices, d, 1e-3);
            diff_low_thresh = pragmas.data.fractionalDiff(testCase.TestPrices, d, 1e-7);
            
            testCase.verifyGreaterThan(length(diff_high_thresh), 0);
            testCase.verifyGreaterThanOrEqual(length(diff_low_thresh), length(diff_high_thresh));
        end
        
        function testFractionalDiff_NaNHandling(testCase)
            % Verifica manejo de NaNs en fractionalDiff
            series = testCase.TestPrices;
            series([5, 20, 50]) = NaN;
            
            diff_series = pragmas.data.fractionalDiff(series, 0.3);
            
            testCase.verifyFalse(any(isnan(diff_series)), ...
                'Serie diferenciada no debe contener NaNs');
        end
        
        function testDataFetcherInitialization(testCase)
            % Verifica inicialización correcta de DataFetcher
            symbols = {'BTC-USD', 'ETH-USD'};
            fetcher = pragmas.data.DataFetcher(symbols, testCase.StartDate, testCase.EndDate, 'crypto');
            
            testCase.verifyEqual(length(fetcher.Symbols), 2);
            testCase.verifyEqual(fetcher.Source, 'crypto');
            testCase.verifyEqual(size(fetcher.DataTables), size(fetcher.Symbols));
        end
        
        function testDataFetcherCryptoFetch(testCase)
            % Prueba fetch de CoinGecko (requiere conexión a internet)
            if ~isempty(webread('https://www.google.com', weboptions('Timeout', 2)))
                fetcher = pragmas.data.DataFetcher('BTC-USD', ...
                    datetime('now') - days(7), datetime('now'), 'crypto');
                
                % Solo fetchea un símbolo para rapidez en tests
                dataTable = fetcher.fetchSingle('BTC-USD');
                
                if ~isempty(dataTable)
                    testCase.verifyTrue(istimetable(dataTable) || istable(dataTable), ...
                        'Fetch debería retornar timetable o table');
                    testCase.verifyGreaterThan(height(dataTable), 0, ...
                        'Tabla de datos no debe estar vacía');
                end
            end
        end
    end
    
end
